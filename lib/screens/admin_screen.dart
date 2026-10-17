import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_theme.dart';
import '../config.dart';
import '../data/links.dart';
import '../data/seed.dart';
import '../services/api.dart';
import '../services/repo.dart';
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
          title: const Text('Admin console · $kBuildLabel'),
          actions: [
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pushNamed('/master'),
              icon: const Icon(Icons.insights_rounded, size: 17),
              label: const Text('Master dashboard'),
            ),
            const SizedBox(width: 6),
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
              Tab(icon: Icon(Icons.health_and_safety_rounded, size: 18), text: 'Overview'),
              Tab(icon: Icon(Icons.group_rounded, size: 18), text: 'Team'),
              Tab(icon: Icon(Icons.smart_toy_rounded, size: 18), text: 'AI engine'),
              Tab(icon: Icon(Icons.hub_rounded, size: 18), text: 'Channels'),
              Tab(icon: Icon(Icons.menu_book_rounded, size: 18), text: 'Knowledge base'),
            ],
          ),
        ),
        body: const TabBarView(children: [
          _Page(child: _OverviewTab()),
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

// ------------------------------------------------------------- overview tab
class _OverviewTab extends StatelessWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _BuildCheck(),
      const DiagnoseCard(),
      _Block(
        icon: Icons.view_sidebar_rounded,
        color: AppTheme.indigo,
        title: 'Desk layout',
        help: 'How a lead opens on the desk (computer / tablet): a side panel on the right, or a large pop-up in the middle. '
            'Both have Minimise and Close. Phones always open the lead full screen.',
        child: StreamBuilder<Map<String, dynamic>>(
          stream: Repo.watchDeskConfig(),
          builder: (context, snap) {
            final view = snap.data?['conversationView'] == 'popup' ? 'popup' : 'panel';
            return Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'panel', icon: Icon(Icons.view_sidebar_rounded), label: Text('Side panel')),
                  ButtonSegment(value: 'popup', icon: Icon(Icons.open_in_new_rounded), label: Text('Pop-up')),
                ],
                selected: {view},
                onSelectionChanged: (v) => Repo.saveDeskLayout(v.first),
              ),
            );
          },
        ),
      ),
      const _Block(
        icon: Icons.currency_rupee_rounded,
        color: AppTheme.success,
        title: 'Enrollment payments (UPI)',
        help: 'After a course is recommended, students see an "Enroll now" button. Asha then shows this UPI QR code for the '
            'registration fee; the student sends a photo of the receipt, and you verify it and allot the course '
            '(Master dashboard or the lead on the desk).',
        child: _PaymentSettings(),
      ),
      // An old demo clock offset would shift every reminder: show a reset only when one is set.
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: Repo.watchDemoConfig(),
        builder: (context, snap) {
          final offset = (snap.data?.data()?['clockOffsetMinutes'] as num?)?.toInt() ?? 0;
          if (offset == 0) return const SizedBox.shrink();
          return Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: ListTile(
              leading: const Icon(Icons.history_toggle_off_rounded, color: AppTheme.hot),
              title: Text('Server clock is ${offset ~/ 60} h ${offset % 60} min ahead (old demo setting)'),
              trailing: FilledButton(onPressed: () => Repo.fastForward(hours: 0), child: const Text('Reset to real time')),
            ),
          );
        },
      ),
      _Block(
        icon: Icons.qr_code_2_rounded,
        color: AppTheme.navy,
        title: 'Channel links and QR codes',
        help: 'Each link tags its own source, so the reports show which channel really produces admissions. '
            'Put a QR on the projector and let judges scan it.',
        child: Wrap(spacing: 18, runSpacing: 18, children: [
          _Qr('WhatsApp (Asha)', PublicLinks.current.value.whatsappUrl),
          _Qr('Telegram bot', PublicLinks.current.value.telegramUrl),
          _Qr('Google Form', PublicLinks.current.value.formUrl),
          _Qr('Website + chat', siteLink()),
          _Qr('Web chat (QR source)', chatLink('qr')),
          _Qr('Website form', formLink('form')),
        ]),
      ),
    ]);
  }
}

/// App build vs backend build: a mismatch means one of the two was not deployed.
class _BuildCheck extends StatelessWidget {
  const _BuildCheck();

  static const _expected = 'r10';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: Api.call('version'),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final server = '${snap.data!['build'] ?? 'old'}';
        final ok = server == _expected;
        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          color: ok ? AppTheme.success.withValues(alpha: 0.08) : AppTheme.hot.withValues(alpha: 0.08),
          child: ListTile(
            leading: Icon(ok ? Icons.verified_rounded : Icons.warning_amber_rounded, color: ok ? AppTheme.success : AppTheme.hot),
            title: Text(ok ? 'App and server are up to date ($kBuildLabel)' : 'Server build "$server" is older than this app ($_expected)'),
            subtitle: ok ? null : const Text('Run "deploy" (or "deploy all") on the laptop, then refresh.'),
          ),
        );
      },
    );
  }
}

class _PaymentSettings extends StatefulWidget {
  const _PaymentSettings();

  @override
  State<_PaymentSettings> createState() => _PaymentSettingsState();
}

class _PaymentSettingsState extends State<_PaymentSettings> {
  final _upi = TextEditingController();
  final _payee = TextEditingController();
  final _amount = TextEditingController(text: '10');
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Repo.watchPayment().first.then((p) {
      if (!mounted) return;
      setState(() {
        _upi.text = '${p['upiId'] ?? ''}';
        _payee.text = '${p['payee'] ?? ''}';
        _amount.text = '${p['amount'] ?? 10}';
        _loaded = true;
      });
    }).catchError((Object _) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _upi.dispose();
    _payee.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    if (!RegExp(r'^[\w.\-]{2,}@[a-zA-Z]{2,}$').hasMatch(_upi.text.trim())) {
      messenger.showSnackBar(const SnackBar(content: Text('Enter a valid UPI ID, e.g. institute@okhdfcbank')));
      return;
    }
    if (amount < 1 || amount > 100000) {
      messenger.showSnackBar(const SnackBar(content: Text('Registration fee must be between ₹1 and ₹1,00,000')));
      return;
    }
    setState(() => _saving = true);
    try {
      await Repo.savePayment(upiId: _upi.text, payee: _payee.text, amount: amount);
      messenger.showSnackBar(SnackBar(content: Text('✅ Saved: students now pay ₹$amount to ${_upi.text.trim()}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('❌ $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const LinearProgressIndicator();
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    final link = 'upi://pay?pa=${Uri.encodeComponent(_upi.text.trim())}&pn=${Uri.encodeComponent(_payee.text.trim())}&am=$amount.00&cu=INR';
    return Wrap(spacing: 24, runSpacing: 16, crossAxisAlignment: WrapCrossAlignment.center, children: [
      SizedBox(
        width: 360,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: _upi, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'UPI ID', hintText: 'institute@okhdfcbank', isDense: true)),
          const SizedBox(height: 10),
          TextField(controller: _payee, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Name shown to the payer', isDense: true)),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Registration fee (₹)', helperText: '₹10 for the demo; change to ₹50 … ₹5,000 any time', isDense: true),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_rounded, size: 18),
            label: const Text('Save payment settings'),
          ),
        ]),
      ),
      if (_upi.text.trim().contains('@'))
        Column(mainAxisSize: MainAxisSize.min, children: [
          Container(color: Colors.white, padding: const EdgeInsets.all(6), child: QrImageView(data: link, size: 150, backgroundColor: Colors.white)),
          const SizedBox(height: 6),
          Text('Preview: ₹$amount', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
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
          decoration: BoxDecoration(
            color: context.scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(AppTheme.r12),
            border: Border.all(color: context.scheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(6),
          child: TextField(
            controller: _kb,
            minLines: 14,
            maxLines: 30,
            style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: context.scheme.onSurface, height: 1.5),
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
