import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_theme.dart';
import '../config.dart';
import '../data/seed.dart';
import '../services/repo.dart';
import '../widgets/simulator.dart';
import '../widgets/site_widgets.dart';
import 'admin/ai_settings_panel.dart';
import 'admin/channels_panel.dart';
import 'team_section.dart';

/// Admin console: the institute controls its own knowledge base, team, AI keys and channels
/// here, and gets the demo tools for the judging round.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: context.scheme.surfaceContainerLow,
        appBar: AppBar(
          title: const Text('Admin console'),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/desk'),
              icon: const Icon(Icons.dashboard_outlined, size: 17),
              label: const Text('Desk'),
            ),
            const SizedBox(width: 10),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.rocket_launch_rounded, size: 18), text: 'Demo'),
              Tab(icon: Icon(Icons.group_rounded, size: 18), text: 'Team'),
              Tab(icon: Icon(Icons.smart_toy_rounded, size: 18), text: 'AI engine'),
              Tab(icon: Icon(Icons.hub_rounded, size: 18), text: 'Channels'),
              Tab(icon: Icon(Icons.menu_book_rounded, size: 18), text: 'Knowledge base'),
            ],
          ),
        ),
        body: const TabBarView(children: [
          _Page(child: _DemoTab()),
          _Page(
            child: _Block(
              icon: Icons.group_add_rounded,
              color: AppTheme.indigo,
              title: 'Team, approvals and languages',
              help: 'Anyone can sign in on the desk with Google or email; they can only work after you approve them. '
                  'Tick the languages each counsellor speaks: new leads are assigned to a counsellor who speaks their language.',
              child: TeamSection(),
            ),
          ),
          _Page(
            child: _Block(
              icon: Icons.smart_toy_rounded,
              color: AppTheme.ai,
              title: 'AI engine — Gemini + free fallbacks',
              help: 'Several free keys, tried in order. Gemini hears voice notes directly; Groq (Whisper) transcribes them for the fallbacks.',
              child: AiSettingsPanel(),
            ),
          ),
          _Page(child: _ChannelsTab()),
          _Page(child: _KbEditor()),
        ]),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 700;
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: phone ? 14 : 28, vertical: 20),
      children: [
        Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1040), child: child)),
      ],
    );
  }
}

// ----------------------------------------------------------------- demo tab
class _DemoTab extends StatefulWidget {
  const _DemoTab();

  @override
  State<_DemoTab> createState() => _DemoTabState();
}

class _DemoTabState extends State<_DemoTab> {
  bool _busy = false;

  Future<void> _run(String done, Future<Object?> Function() job) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await job();
      messenger.showSnackBar(SnackBar(content: Text('✅ $done${r is Map ? ' · ${r.entries.where((e) => e.key != 'ok').map((e) => '${e.key}: ${e.value}').join(', ')}' : ''}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('❌ $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_busy) const LinearProgressIndicator(minHeight: 3),
      _Block(
        icon: Icons.dataset_rounded,
        color: AppTheme.ai,
        title: 'Demo data',
        help: 'Loads the sample knowledge base, a 7-day calendar of demo classes + counsellor call slots, and 30 SAMPLE leads '
            '(English, Hindi, Marathi, mixed; every channel; objections, scores, bookings) so the desk and reports look alive. '
            'Sample leads are marked and removed with one click.',
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(
            icon: const Icon(Icons.bolt_rounded, size: 18),
            label: const Text('Load everything'),
            onPressed: _busy ? null : () => _run('Demo data loaded', () => Repo.seed('all')),
          ),
          OutlinedButton(onPressed: _busy ? null : () => _run('Knowledge base loaded', () => Repo.seed('kb')), child: const Text('Courses only')),
          OutlinedButton(onPressed: _busy ? null : () => _run('Slots created', () => Repo.seed('slots')), child: const Text('Demo & call slots')),
          OutlinedButton(onPressed: _busy ? null : () => _run('Sample leads loaded', () => Repo.seed('leads')), child: const Text('30 sample leads')),
          TextButton.icon(
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            onPressed: _busy ? null : () => _run('Sample leads removed', Repo.clearSeed),
            label: const Text('Clear sample leads'),
          ),
        ]),
      ),
      _Block(
        icon: Icons.science_rounded,
        color: AppTheme.coral,
        title: 'Simulate an enquiry',
        help: 'WhatsApp, Instagram, Telegram, a phone call, a Google Form or the website form — exactly as if it arrived there. '
            'Run the Rahul Patil presets 1 → 2 → 3 to show the same person recognised across channels and scripts.',
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => showSimulator(context),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.coral),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Open the simulator'),
          ),
        ),
      ),
      _Block(
        icon: Icons.speed_rounded,
        color: AppTheme.hot,
        title: 'Load test: many people at the same moment',
        help: 'Creates N anonymous website visitors who all write at once, asking 3 common questions (like real traffic). '
            'Watch the desk fill up, then open Reports → Scale & cost: identical questions are answered with one AI call '
            '(single-flight cache), so 30 people cost about 3 AI calls. Load-test leads are removed by "Clear sample leads".',
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          for (final n in const [10, 30, 100])
            FilledButton.tonal(
              onPressed: _busy ? null : () => _run('$n enquiries sent at once', () => Repo.burst(n)),
              child: Text('$n at once'),
            ),
          TextButton(onPressed: _busy ? null : () => _run('Counters reset', Repo.resetStats), child: const Text('Reset counters')),
        ]),
      ),
      _Block(
        icon: Icons.fast_forward_rounded,
        color: AppTheme.warm,
        title: 'Time machine (demo only)',
        help: 'Moves the server clock forward and runs reminders and follow-ups immediately, so judges see "no lead forgotten" '
            'without waiting a day.',
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: Repo.watchDemoConfig(),
          builder: (context, snap) {
            final offset = (snap.data?.data()?['clockOffsetMinutes'] as num?)?.toInt() ?? 0;
            final last = snap.data?.data()?['lastRun'];
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                SmallInfo('Clock offset: ${offset ~/ 60} h ${offset % 60} min'),
                if (last != null) SmallInfo('Last run: $last'),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                FilledButton.tonal(onPressed: () => Repo.fastForward(hours: 3), child: const Text('+3 hours')),
                FilledButton.tonal(onPressed: () => Repo.fastForward(hours: 24), child: const Text('+1 day')),
                FilledButton.tonal(onPressed: () => Repo.fastForward(hours: 48), child: const Text('+2 days')),
                OutlinedButton(onPressed: () => Repo.fastForward(hours: 0), child: const Text('Reset')),
              ]),
            ]);
          },
        ),
      ),
      _Block(
        icon: Icons.qr_code_2_rounded,
        color: AppTheme.navy,
        title: 'Channel links and QR codes',
        help: 'Each link tags its own source, so the reports show which channel really produces admissions. '
            'Put a QR on the projector and let judges scan it.',
        child: Wrap(spacing: 18, runSpacing: 18, children: [
          _Qr('Website + chat', siteLink()),
          _Qr('Web chat (QR source)', chatLink('qr')),
          _Qr('Instagram bio link', chatLink('instagram')),
          _Qr('Website form', formLink('form')),
        ]),
      ),
    ]);
  }
}

class _ChannelsTab extends StatelessWidget {
  const _ChannelsTab();

  @override
  Widget build(BuildContext context) => const _Block(
        icon: Icons.hub_rounded,
        color: AppTheme.info,
        title: 'Where enquiries arrive',
        help: 'Connect each channel once. Every channel lands in the same lead timeline, the same AI brain answers, '
            'and the same person is recognised across channels.',
        child: ChannelsPanel(),
      );
}

// ------------------------------------------------------- knowledge base tab
class _KbEditor extends StatefulWidget {
  const _KbEditor();

  @override
  State<_KbEditor> createState() => _KbEditorState();
}

class _KbEditorState extends State<_KbEditor> {
  final _kb = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Repo.db.doc('kb/main').get().then((s) {
      final data = Map<String, dynamic>.from(s.data() ?? sampleKnowledgeBase)..remove('updatedAt');
      if (!mounted) return;
      setState(() {
        _kb.text = const JsonEncoder.withIndent('  ').convert(data);
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _kb.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(_kb.text) as Map<String, dynamic>;
      if (parsed['courses'] is! List) throw const FormatException('"courses" must be a list');
    } catch (e) {
      _snack('Not valid JSON: $e');
      return;
    }
    try {
      await Repo.db.doc('kb/main').set({...parsed, 'updatedAt': FieldValue.serverTimestamp()});
      _snack('✅ Saved. The website and Asha both use it right away.');
    } catch (e) {
      _snack('❌ $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Block(
      icon: Icons.menu_book_rounded,
      color: AppTheme.human,
      title: 'Knowledge base — the institute controls this',
      help: 'Asha may only quote fees, EMIs, scholarships, batches and policies written here, and the Guard blocks any other '
          'amount, percentage or guarantee. The website reads the same document, so the two can never disagree.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!_loaded) const LinearProgressIndicator(),
        Container(
          decoration: BoxDecoration(color: const Color(0xFF0B1220), borderRadius: BorderRadius.circular(AppTheme.r12)),
          padding: const EdgeInsets.all(6),
          child: TextField(
            controller: _kb,
            minLines: 14,
            maxLines: 30,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: Color(0xFFE2E8F0), height: 1.5),
            decoration: const InputDecoration(filled: false, border: InputBorder.none, contentPadding: EdgeInsets.all(10)),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 10, children: [
          FilledButton.icon(icon: const Icon(Icons.save_rounded, size: 18), label: const Text('Save knowledge base'), onPressed: _save),
          TextButton(
            onPressed: () => setState(() => _kb.text = const JsonEncoder.withIndent('  ').convert(sampleKnowledgeBase)),
            child: const Text('Reset to sample'),
          ),
        ]),
      ]),
    );
  }
}

// ------------------------------------------------------------------ pieces
class _Block extends StatelessWidget {
  const _Block({required this.icon, required this.color, required this.title, required this.help, required this.child});

  final IconData icon;
  final Color color;
  final String title;
  final String help;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: context.scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.r20),
        border: Border.all(color: context.scheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconBadge(icon: icon, color: color, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: context.texts.titleMedium),
              const SizedBox(height: 4),
              Text(help, style: context.texts.bodyMedium?.copyWith(fontSize: 13.2)),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        child,
      ]),
    );
  }
}

class _Qr extends StatelessWidget {
  const _Qr(this.label, this.url);
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.r16), border: Border.all(color: context.scheme.outlineVariant)),
          child: QrImageView(data: url, size: 150, backgroundColor: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(label, textAlign: TextAlign.center, style: context.texts.titleSmall?.copyWith(fontSize: 13)),
        TextButton.icon(
          icon: const Icon(Icons.copy_rounded, size: 14),
          label: const Text('Copy link', style: TextStyle(fontSize: 12)),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied $url')));
          },
        ),
      ]),
    );
  }
}

class SmallInfo extends StatelessWidget {
  const SmallInfo(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: context.scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );
}
