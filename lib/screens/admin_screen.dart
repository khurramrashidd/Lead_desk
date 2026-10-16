import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_theme.dart';
import '../config.dart';
import '../data/seed.dart';
import '../services/repo.dart';
import '../utils/responsive.dart';
import '../widgets/site_widgets.dart';
import 'team_section.dart';

/// Admin console: the institute controls its own knowledge base here, approves
/// counsellors, and gets the demo tools for the judging round.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _kb = TextEditingController();
  bool _kbLoaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Repo.db.doc('kb/main').get().then((s) {
      final data = Map<String, dynamic>.from(s.data() ?? sampleKnowledgeBase)..remove('updatedAt');
      if (!mounted) return;
      setState(() {
        _kb.text = const JsonEncoder.withIndent('  ').convert(data);
        _kbLoaded = true;
      });
    });
  }

  @override
  void dispose() {
    _kb.dispose();
    super.dispose();
  }

  Future<void> _run(String done, Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
      _snack('✅ $done');
    } catch (e) {
      _snack('❌ Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveKb() async {
    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(_kb.text) as Map<String, dynamic>;
      if (parsed['courses'] is! List) throw const FormatException('"courses" must be a list');
    } catch (e) {
      _snack('Not valid JSON: $e');
      return;
    }
    await _run('Knowledge base saved. Asha uses it from her next message.', () async {
      await Repo.db.doc('kb/main').set({...parsed, 'updatedAt': FieldValue.serverTimestamp()});
    });
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
    return Scaffold(
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
      ),
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.symmetric(horizontal: phone ? 16 : 28, vertical: 20),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Block(
                        icon: Icons.group_add_rounded,
                        color: AppTheme.indigo,
                        title: 'Team and counsellor requests',
                        help: 'Anyone can sign in on the desk with Google or email. They can only work after you approve them here.',
                        child: const TeamSection(),
                      ),
                      _Block(
                        icon: Icons.dataset_rounded,
                        color: AppTheme.ai,
                        title: 'Demo data',
                        help: 'Loads the sample courses, a 7-day demo-class calendar and realistic leads so the desk and reports look alive.',
                        child: Wrap(spacing: 10, runSpacing: 10, children: [
                          FilledButton.icon(
                            icon: const Icon(Icons.bolt_rounded, size: 18),
                            label: const Text('Load everything'),
                            onPressed: _busy
                                ? null
                                : () => _run('All demo data loaded', () async {
                                      await Seed.loadKnowledgeBase();
                                      await Seed.loadSlots();
                                      await Seed.loadDemoLeads();
                                    }),
                          ),
                          OutlinedButton(
                            onPressed: _busy ? null : () => _run('Courses loaded', Seed.loadKnowledgeBase),
                            child: const Text('Courses only'),
                          ),
                          OutlinedButton(
                            onPressed: _busy ? null : () => _run('Demo slots created', () async => Seed.loadSlots()),
                            child: const Text('Demo-class slots'),
                          ),
                          OutlinedButton(
                            onPressed: _busy ? null : () => _run('Demo leads loaded', Seed.loadDemoLeads),
                            child: const Text('Demo leads'),
                          ),
                        ]),
                      ),
                      _Block(
                        icon: Icons.qr_code_2_rounded,
                        color: AppTheme.navy,
                        title: 'Channel links and QR codes',
                        help: 'Each link tags its own source, so the reports can show which channel really produces admissions. '
                            'Put a QR on the projector and let judges scan it.',
                        child: Wrap(spacing: 18, runSpacing: 18, children: [
                          _Qr('Website + chat', siteLink(), onCopy: _snack),
                          _Qr('Web chat (QR source)', chatLink('qr'), onCopy: _snack),
                          _Qr('Instagram bio link', chatLink('instagram'), onCopy: _snack),
                          _Qr('Website form', formLink('form'), onCopy: _snack),
                        ]),
                      ),
                      _Block(
                        icon: Icons.fast_forward_rounded,
                        color: AppTheme.warm,
                        title: 'Time machine (demo only)',
                        help: 'Moves the server clock forward and runs reminders and follow-ups immediately, so judges see '
                            '"no lead forgotten" without waiting a day.',
                        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: Repo.watchDemoConfig(),
                          builder: (context, snap) {
                            final offset = (snap.data?.data()?['clockOffsetMinutes'] as num?)?.toInt() ?? 0;
                            final last = snap.data?.data()?['lastRun'];
                            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                SmallInfo('Clock offset: ${offset ~/ 60} h ${offset % 60} min'),
                                if (last != null) ...[const SizedBox(width: 8), SmallInfo('Last run: $last')],
                              ]),
                              const SizedBox(height: 12),
                              Wrap(spacing: 10, children: [
                                FilledButton.tonal(
                                    onPressed: () => Repo.fastForward(hours: 24), child: const Text('+1 day')),
                                FilledButton.tonal(
                                    onPressed: () => Repo.fastForward(hours: 48), child: const Text('+2 days')),
                                OutlinedButton(
                                    onPressed: () => Repo.fastForward(hours: 0), child: const Text('Reset')),
                              ]),
                            ]);
                          },
                        ),
                      ),
                      _Block(
                        icon: Icons.menu_book_rounded,
                        color: AppTheme.human,
                        title: 'Knowledge base — the institute controls this',
                        help: 'Asha may only quote fees, EMIs, scholarships, batches and policies written here. '
                            'The website reads the same data, so the two can never disagree.',
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          if (!_kbLoaded) const LinearProgressIndicator(),
                          Container(
                            decoration: BoxDecoration(
                              color: context.isDark ? const Color(0xFF0C0D14) : const Color(0xFF111322),
                              borderRadius: BorderRadius.circular(AppTheme.r12),
                            ),
                            padding: const EdgeInsets.all(6),
                            child: TextField(
                              controller: _kb,
                              minLines: 12,
                              maxLines: 26,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: Color(0xFFE2E8F0), height: 1.5),
                              decoration: const InputDecoration(
                                filled: false,
                                border: InputBorder.none,
                                hintText: '{ "instituteName": …, "courses": [...] }',
                                contentPadding: EdgeInsets.all(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(children: [
                            FilledButton.icon(
                              icon: const Icon(Icons.save_rounded, size: 18),
                              label: const Text('Save knowledge base'),
                              onPressed: _busy ? null : _saveKb,
                            ),
                            const SizedBox(width: 10),
                            TextButton(
                              onPressed: () => setState(
                                () => _kb.text = const JsonEncoder.withIndent('  ').convert(sampleKnowledgeBase),
                              ),
                              child: const Text('Reset to sample'),
                            ),
                          ]),
                        ]),
                      ),
                      _Block(
                        icon: Icons.chat_rounded,
                        color: const Color(0xFF25D366),
                        title: 'WhatsApp channel',
                        help: 'Webhook URL: the whatsappWebhook function URL printed by deploy. '
                            'Verify token: the WA_VERIFY_TOKEN value in functions/.env. Full steps are in docs/WHATSAPP_SETUP.md.',
                        child: Text(
                          'Meta\'s free test number reaches up to 5 verified phones — use your own for the demo. '
                          'Free-form replies are allowed for 24 hours after the student\'s last message; '
                          'outside that window the desk flags the lead instead of silently failing.',
                          style: context.texts.bodyMedium?.copyWith(fontSize: 13.5),
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_busy) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 3)),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.icon,
    required this.color,
    required this.title,
    required this.help,
    required this.child,
  });

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
        ],
      ),
    );
  }
}

class _Qr extends StatelessWidget {
  const _Qr(this.label, this.url, {required this.onCopy});
  final String label;
  final String url;
  final void Function(String) onCopy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTheme.r16),
            border: Border.all(color: context.scheme.outlineVariant),
          ),
          child: QrImageView(data: url, size: 150, backgroundColor: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(label, textAlign: TextAlign.center, style: context.texts.titleSmall?.copyWith(fontSize: 13)),
        TextButton.icon(
          icon: const Icon(Icons.copy_rounded, size: 14),
          label: const Text('Copy link', style: TextStyle(fontSize: 12)),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            onCopy('Copied $url');
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
        decoration: BoxDecoration(
          color: context.scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );
}
