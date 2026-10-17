import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../services/ops_service.dart';
import '../../utils/ist.dart';

/// Admin → AI engine: a pool of free keys (Gemini first, then Groq and OpenRouter), tried in
/// order, so one rate-limited key never stops a conversation during judging.
class AiSettingsPanel extends StatefulWidget {
  const AiSettingsPanel({super.key});

  @override
  State<AiSettingsPanel> createState() => _AiSettingsPanelState();
}

class _AiSettingsPanelState extends State<AiSettingsPanel> {
  final _label = TextEditingController();
  final _key = TextEditingController();
  final _model = TextEditingController(text: AiProvider.modelsFor['gemini']!.first);
  String _kind = 'gemini';
  bool _busy = false;
  List<Map<String, dynamic>> _env = const [];

  @override
  void initState() {
    super.initState();
    OpsService.envProviders().then((v) {
      if (mounted) setState(() => _env = v);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _label.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _guard(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      _snack('❌ $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test(String kind, String key, String model) => _guard(() async {
        final r = await OpsService.testAiKey(kind, key, model);
        _snack(r.ok ? '✅ $kind · $model answered in ${r.ms} ms' : '❌ $kind · $model: ${r.detail}');
      });

  Future<void> _add(List<AiProvider> current) => _guard(() async {
        final key = _key.text.trim();
        if (key.isEmpty) throw 'Paste an API key first';
        final p = AiProvider(
          id: UniqueKeyish.next(),
          label: _label.text.trim().isEmpty ? '$_kind key ${current.length + 1}' : _label.text.trim(),
          apiKey: key,
          model: _model.text.trim().isEmpty ? AiProvider.modelsFor[_kind]!.first : _model.text.trim(),
          kind: _kind,
        );
        await OpsService.saveProviders([...current, p]);
        _key.clear();
        _label.clear();
        _snack('✅ Added. Asha uses it from the next message.');
      });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: OpsService.watchAi(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final providers = OpsService.providersFrom(data);
        final thinking = (data?['thinking'] as String?) ?? 'MINIMAL';
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            'Order matters: the first key answers; if it is rate-limited or wrong, the next one does. Voice notes need Gemini, '
            'or a Groq key (Whisper transcribes them for Groq/OpenRouter). Keys from functions/.env are always added at the end.',
            style: context.texts.bodySmall?.copyWith(fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: OpsService.watchAiHealth(),
            builder: (context, hs) {
              final health = hs.data?.data() ?? const <String, dynamic>{};
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < providers.length; i++) _row(context, providers, i, (health[providers[i].id] as Map?)?.cast<String, dynamic>(), health['lastUsed'] == providers[i].id),
                for (final e in _env)
                  _envRow(context, e, (health['${e['id']}'] as Map?)?.cast<String, dynamic>(), health['lastUsed'] == e['id']),
                if (providers.isEmpty && _env.isEmpty)
                  Text('No keys yet. Add one below or put GEMINI_API_KEY in functions/.env.', style: TextStyle(color: AppTheme.hot, fontSize: 13)),
                _lastFailure(context, (health['lastFailure'] as Map?)?.cast<String, dynamic>()),
              ]);
            },
          ),
          const Divider(height: 28),
          Text('Add a key', style: context.texts.titleSmall),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                key: ValueKey('kind_$_kind'),
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Provider', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
                  DropdownMenuItem(value: 'groq', child: Text('Groq (free)')),
                  DropdownMenuItem(value: 'openrouter', child: Text('OpenRouter (free)')),
                ],
                onChanged: (v) => setState(() {
                  _kind = v ?? 'gemini';
                  _model.text = AiProvider.modelsFor[_kind]!.first;
                }),
              ),
            ),
            SizedBox(width: 180, child: TextField(controller: _label, decoration: const InputDecoration(labelText: 'Label (optional)', isDense: true))),
            SizedBox(width: 300, child: TextField(controller: _key, obscureText: true, decoration: const InputDecoration(labelText: 'API key', isDense: true))),
            SizedBox(
              width: 260,
              child: TextField(
                controller: _model,
                decoration: InputDecoration(
                  labelText: 'Model',
                  isDense: true,
                  suffixIcon: PopupMenuButton<String>(
                    tooltip: 'Suggested models',
                    icon: const Icon(Icons.arrow_drop_down_rounded),
                    onSelected: (m) => setState(() => _model.text = m),
                    itemBuilder: (_) => [for (final m in AiProvider.modelsFor[_kind]!) PopupMenuItem(value: m, child: Text(m))],
                  ),
                ),
              ),
            ),
            OutlinedButton(onPressed: _busy ? null : () => _test(_kind, _key.text.trim(), _model.text.trim()), child: const Text('Test')),
            FilledButton.icon(onPressed: _busy ? null : () => _add(providers), icon: const Icon(Icons.add, size: 18), label: const Text('Add to pool')),
          ]),
          const SizedBox(height: 6),
          Text('Free keys: aistudio.google.com · console.groq.com/keys · openrouter.ai/keys', style: context.texts.bodySmall?.copyWith(fontSize: 12)),
          const Divider(height: 28),
          Row(children: [
            Text('Thinking', style: context.texts.titleSmall),
            const SizedBox(width: 12),
            Expanded(
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'MINIMAL', label: Text('Fastest')),
                  ButtonSegment(value: 'LOW', label: Text('Low')),
                  ButtonSegment(value: 'MEDIUM', label: Text('Medium')),
                ],
                selected: {thinking == 'HIGH' ? 'MEDIUM' : thinking},
                onSelectionChanged: (s) => OpsService.saveThinking(s.first),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: _busy
                  ? null
                  : () => _guard(() async {
                        final r = await OpsService.warmUp();
                        _snack('🔥 Warmed up: $r');
                      }),
              icon: const Icon(Icons.local_fire_department_rounded, size: 18),
              label: const Text('Warm up (do this 2 minutes before judging)'),
            ),
          ),
        ]);
      },
    );
  }

  /// Why Asha last could not answer at all (every key failed), so a wrong key or model is obvious.
  Widget _lastFailure(BuildContext context, Map<String, dynamic>? f) {
    if (f == null) return const SizedBox.shrink();
    final at = Ist.fromTimestamp(f['at']);
    final errors = ((f['errors'] as List?) ?? const []).map((e) => '$e').toList();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warm.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.r12),
        border: Border.all(color: AppTheme.warm.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          '⚠️ Last time every key failed${at == null ? '' : ' (${Ist.relative(at)})'}. Asha answered from the knowledge base and retried. '
          'Fix: press Test on each key; replace any key or model that fails.',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
        ),
        const SizedBox(height: 6),
        for (final e in errors.take(6)) Text('• $e', style: context.texts.bodySmall?.copyWith(fontSize: 11.5)),
      ]),
    );
  }

  Widget _health(BuildContext context, Map<String, dynamic>? h, bool lastUsed) {
    if (h == null) return Text('not used yet', style: context.texts.bodySmall?.copyWith(fontSize: 11.5));
    final ok = h['ok'] == true;
    final at = Ist.fromTimestamp(h['at']);
    return Text(
      '${ok ? '✅' : '⚠️'} ${ok ? '${h['ms']} ms' : '${h['detail']}'}${at == null ? '' : ' · ${Ist.relative(at)}'}${lastUsed ? ' · last used' : ''}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11.5, color: ok ? AppTheme.success : AppTheme.warm),
    );
  }

  Widget _row(BuildContext context, List<AiProvider> all, int i, Map<String, dynamic>? h, bool lastUsed) {
    final p = all[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(children: [
          Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p.label} · ${p.kind} · ${p.model}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              Text(p.maskedKey, style: context.texts.bodySmall?.copyWith(fontSize: 11.5)),
              _health(context, h, lastUsed),
            ]),
          ),
          Switch(
            value: p.enabled,
            onChanged: (v) {
              p.enabled = v;
              OpsService.saveProviders(all);
            },
          ),
          IconButton(tooltip: 'Test', icon: const Icon(Icons.play_arrow_rounded), onPressed: _busy ? null : () => _test(p.kind, p.apiKey, p.model)),
          IconButton(
            tooltip: 'Move up',
            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
            onPressed: i == 0
                ? null
                : () {
                    final list = [...all];
                    final x = list.removeAt(i);
                    list.insert(i - 1, x);
                    OpsService.saveProviders(list);
                  },
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
            onPressed: () => OpsService.saveProviders([...all]..removeAt(i)),
          ),
        ]),
      ),
    );
  }

  Widget _envRow(BuildContext context, Map<String, dynamic> e, Map<String, dynamic>? h, bool lastUsed) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: context.scheme.surfaceContainer,
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.lock_outline_rounded, size: 18),
          title: Text('${e['label']} · ${e['model']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          subtitle: _health(context, h, lastUsed),
        ),
      );
}
