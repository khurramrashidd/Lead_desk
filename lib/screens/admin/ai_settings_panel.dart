import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../services/ops_service.dart';
import '../../utils/ist.dart';
import '../../widgets/site_widgets.dart';

/// Admin → AI engine.
///
/// Several Gemini keys can be listed here, each with its own model. They are
/// tried top to bottom: if one is rate-limited or out of free quota, the next
/// answers, so a demo never dies because one key ran dry.
class AiSettingsPanel extends StatefulWidget {
  const AiSettingsPanel({super.key});

  @override
  State<AiSettingsPanel> createState() => _AiSettingsPanelState();
}

class _AiSettingsPanelState extends State<AiSettingsPanel> {
  bool _busy = false;

  void _snack(String m, {bool bad = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: bad ? context.scheme.error : null,
        duration: Duration(seconds: bad ? 8 : 4),
      ),
    );
  }

  Future<void> _edit(List<AiProvider> all, AiProvider? existing) async {
    final result = await showDialog<AiProvider>(
      context: context,
      builder: (_) => _ProviderDialog(provider: existing),
    );
    if (result == null) return;
    final next = [...all];
    final i = next.indexWhere((p) => p.id == result.id);
    if (i >= 0) {
      next[i] = result;
    } else {
      next.add(result);
    }
    await _save(next, 'Saved');
  }

  Future<void> _save(List<AiProvider> providers, String done) async {
    setState(() => _busy = true);
    try {
      await OpsService.saveProviders(providers);
      _snack(done);
    } catch (e) {
      _snack('Could not save: $e', bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test(AiProvider p) async {
    setState(() => _busy = true);
    try {
      final r = await OpsService.testAiKey(p.apiKey, p.model);
      _snack(r.ok ? '✅ ${p.label.isEmpty ? p.model : p.label} answered in ${r.ms} ms' : '❌ ${r.detail}', bad: !r.ok);
    } catch (e) {
      _snack('Test failed: $e', bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: OpsService.watchAi(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final providers = OpsService.providersFrom(data);
        final thinking = data?['thinking'] as String? ?? 'MINIMAL';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const Padding(padding: EdgeInsets.only(bottom: 10), child: LinearProgressIndicator(minHeight: 3)),

            if (providers.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.warm.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(AppTheme.r12),
                  border: Border.all(color: AppTheme.warm.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'No keys added here yet — the key in functions/.env is being used. '
                  'Add two or three free keys so one running out never stops the demo.',
                  style: context.texts.bodyMedium?.copyWith(fontSize: 13.2),
                ),
              ),

            for (var i = 0; i < providers.length; i++)
              _ProviderRow(
                provider: providers[i],
                position: i,
                total: providers.length,
                onEdit: () => _edit(providers, providers[i]),
                onTest: () => _test(providers[i]),
                onToggle: (v) {
                  final next = [...providers];
                  next[i].enabled = v;
                  _save(next, v ? 'Enabled' : 'Disabled');
                },
                onMove: (delta) {
                  final next = [...providers];
                  final j = i + delta;
                  if (j < 0 || j >= next.length) return;
                  final tmp = next[i];
                  next[i] = next[j];
                  next[j] = tmp;
                  _save(next, 'Order updated');
                },
                onDelete: () {
                  final next = [...providers]..removeAt(i);
                  _save(next, 'Removed');
                },
              ),

            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _edit(providers, null),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add a Gemini key'),
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          final n = await OpsService.warmUp();
                          _snack('Brain warmed up · $n provider(s) ready');
                        } catch (e) {
                          _snack('Warm-up failed: $e', bad: true);
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                icon: const Icon(Icons.local_fire_department_outlined, size: 18),
                label: const Text('Warm up before the demo'),
              ),
            ]),

            const SizedBox(height: 20),
            Text('Answer speed', style: context.texts.titleSmall),
            const SizedBox(height: 4),
            Text(
              'How long the model may think before replying. Minimal is the fastest and is right for '
              'counselling chat; raise it only if answers feel shallow.',
              style: context.texts.bodySmall?.copyWith(fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<String>(
                style: SegmentedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                segments: const [
                  ButtonSegment(value: 'MINIMAL', label: Text('Fastest')),
                  ButtonSegment(value: 'LOW', label: Text('Balanced')),
                  ButtonSegment(value: 'MEDIUM', label: Text('Thorough')),
                ],
                selected: {thinking},
                onSelectionChanged: (s) => OpsService.saveThinking(s.first),
              ),
            ),

            const SizedBox(height: 20),
            const _HealthStrip(),
          ],
        );
      },
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.provider,
    required this.position,
    required this.total,
    required this.onEdit,
    required this.onTest,
    required this.onToggle,
    required this.onMove,
    required this.onDelete,
  });

  final AiProvider provider;
  final int position;
  final int total;
  final VoidCallback onEdit;
  final VoidCallback onTest;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onMove;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dim = !provider.enabled;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: context.scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.r12),
        border: Border.all(color: context.scheme.outlineVariant),
      ),
      child: Opacity(
        opacity: dim ? 0.55 : 1,
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: position == 0 ? AppTheme.human.withValues(alpha: 0.15) : context.scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${position + 1}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: position == 0 ? AppTheme.human : context.scheme.onSurfaceVariant)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.label.isEmpty ? 'Key ${position + 1}' : provider.label,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text('${provider.model}  ·  ${provider.maskedKey}',
                      style: context.texts.bodySmall?.copyWith(fontSize: 12)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Move up',
              visualDensity: VisualDensity.compact,
              onPressed: position == 0 ? null : () => onMove(-1),
              icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
            ),
            IconButton(
              tooltip: 'Move down',
              visualDensity: VisualDensity.compact,
              onPressed: position == total - 1 ? null : () => onMove(1),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
            ),
            Switch(value: provider.enabled, onChanged: onToggle),
            IconButton(tooltip: 'Test', onPressed: onTest, icon: const Icon(Icons.bolt_rounded, size: 19)),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Remove')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderDialog extends StatefulWidget {
  const _ProviderDialog({this.provider});
  final AiProvider? provider;

  @override
  State<_ProviderDialog> createState() => _ProviderDialogState();
}

class _ProviderDialogState extends State<_ProviderDialog> {
  late final _label = TextEditingController(text: widget.provider?.label ?? '');
  late final _key = TextEditingController(text: widget.provider?.apiKey ?? '');
  late String _model = widget.provider?.model ?? AiProvider.commonModels.first;
  final _custom = TextEditingController();
  bool _useCustom = false;
  bool _testing = false;
  String? _result;

  @override
  void initState() {
    super.initState();
    if (widget.provider != null && !AiProvider.commonModels.contains(widget.provider!.model)) {
      _useCustom = true;
      _custom.text = widget.provider!.model;
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _key.dispose();
    _custom.dispose();
    super.dispose();
  }

  String get _chosenModel => _useCustom ? _custom.text.trim() : _model;

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      final r = await OpsService.testAiKey(_key.text.trim(), _chosenModel);
      setState(() => _result = r.ok ? '✅ Works — answered in ${r.ms} ms' : '❌ ${r.detail}');
    } catch (e) {
      setState(() => _result = '❌ $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.provider == null ? 'Add a Gemini key' : 'Edit key'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Get a free key at aistudio.google.com → Get API key. '
                'Keys from different Google accounts give you separate free quotas.',
                style: context.texts.bodySmall?.copyWith(fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Label', hintText: 'e.g. Khurram personal'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _key,
                decoration: const InputDecoration(labelText: 'API key', hintText: 'AIza… or AQ.…'),
                maxLines: 1,
              ),
              const SizedBox(height: 16),
              Text('Model', style: context.texts.titleSmall),
              const SizedBox(height: 8),
              if (!_useCustom)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final m in AiProvider.commonModels)
                    ChoiceChip(
                      label: Text(m),
                      selected: _model == m,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _model = m),
                    ),
                ])
              else
                TextField(
                  controller: _custom,
                  decoration: const InputDecoration(labelText: 'Model name', hintText: 'gemini-…'),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _useCustom = !_useCustom),
                  icon: Icon(_useCustom ? Icons.list_rounded : Icons.edit_rounded, size: 16),
                  label: Text(_useCustom ? 'Pick from the list' : 'Type a model name'),
                ),
              ),
              if (_result != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_result!, style: const TextStyle(fontSize: 12.5, height: 1.5)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        OutlinedButton.icon(
          onPressed: _testing || _key.text.trim().isEmpty ? null : _test,
          icon: _testing
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.bolt_rounded, size: 17),
          label: const Text('Test'),
        ),
        FilledButton(
          onPressed: () {
            if (_key.text.trim().isEmpty || _chosenModel.isEmpty) return;
            Navigator.pop(
              context,
              AiProvider(
                id: widget.provider?.id ?? UniqueKeyish.next(),
                label: _label.text.trim(),
                apiKey: _key.text.trim(),
                model: _chosenModel,
                enabled: widget.provider?.enabled ?? true,
                order: widget.provider?.order ?? 0,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// What actually happened on the last few calls — the honest view.
class _HealthStrip extends StatelessWidget {
  const _HealthStrip();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: OpsService.watchAiHealth(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final entries = data.entries.where((e) => e.value is Map).toList();
        if (entries.isEmpty) {
          return Text('No AI calls yet.', style: context.texts.bodySmall?.copyWith(fontSize: 12.5));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last result per key', style: context.texts.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in entries)
                  Builder(builder: (context) {
                    final m = (e.value as Map).cast<String, dynamic>();
                    final ok = m['ok'] == true;
                    final c = ok ? AppTheme.human : AppTheme.hot;
                    return Tooltip(
                      message: '${m['detail'] ?? ''}',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: c.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: c.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '${ok ? '✅' : '❌'} ${e.key} · ${m['model'] ?? ''} · ${m['ms'] ?? '?'} ms'
                          '${Ist.fromTimestamp(m['at']) == null ? '' : ' · ${Ist.relative(Ist.fromTimestamp(m['at']))}'}',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c),
                        ),
                      ),
                    );
                  }),
              ],
            ),
            const SizedBox(height: 10),
            const DemoNote('Keys are stored in Firestore and readable only by admins.'),
          ],
        );
      },
    );
  }
}
