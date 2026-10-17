import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_theme.dart';
import '../../data/links.dart';
import '../../services/api.dart';
import '../../services/ops_service.dart';

/// Admin → Channels: every place an enquiry can arrive, connected from one screen.
/// Values are saved to Firestore config/channels (admins only) and read by the Cloud
/// Functions, so connecting a channel never needs a redeploy.
class ChannelsPanel extends StatefulWidget {
  const ChannelsPanel({super.key});

  @override
  State<ChannelsPanel> createState() => _ChannelsPanelState();
}

class _ChannelsPanelState extends State<ChannelsPanel> {
  final _c = <String, TextEditingController>{
    for (final k in ['waToken', 'waPhoneId', 'waVerifyToken', 'waBusinessId', 'telegramBotToken', 'igToken', 'igUserId', 'calendarId', 'intakeSecret'])
      k: TextEditingController(),
  };
  bool _loaded = false;
  bool _busy = false;
  bool _onboarding = true;
  String _serviceAccount = '';
  final _status = <String, String>{};

  @override
  void initState() {
    super.initState();
    OpsService.channelsDoc.get().then((s) {
      final d = s.data() ?? const <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        for (final e in _c.entries) {
          e.value.text = '${d[e.key] ?? ''}';
        }
        if (_c['waVerifyToken']!.text.isEmpty) _c['waVerifyToken']!.text = 'leaddesk-verify-123';
        if (_c['intakeSecret']!.text.isEmpty) _c['intakeSecret']!.text = 'leaddesk-intake-123';
        _onboarding = d['onboarding'] != false;
        _loaded = true;
      });
    }).catchError((Object e) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _save({bool quiet = false}) async {
    await OpsService.saveChannels({for (final e in _c.entries) e.key: e.value.text.trim()});
    if (!quiet) _snack('✅ Channels saved');
  }

  Future<void> _check(String key, Future<String> Function() job) async {
    setState(() => _busy = true);
    try {
      await _save(quiet: true);
      final r = await job();
      setState(() => _status[key] = r);
    } catch (e) {
      setState(() => _status[key] = '❌ $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _base => Api.functionsBase;

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const LinearProgressIndicator();
    final secret = _c['intakeSecret']!.text.trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _DiagnoseCard(),
      const _PublicLinksCard(),
      Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: SwitchListTile(
          value: _onboarding,
          title: const Text('Intake questions before counselling', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text(
            'New chats on WhatsApp, Telegram and the website first get: who is this for (student / parent / friend) → '
            'student\'s name → mobile or email → the course list. Then Asha counsels about the chosen course. '
            'Turn off to let Asha answer the first message directly.',
          ),
          onChanged: (v) async {
            setState(() => _onboarding = v);
            await OpsService.saveChannels({'onboarding': v});
            _snack(v ? '✅ Intake questions on' : 'Intake questions off');
          },
        ),
      ),
      _Channel(
        color: const Color(0xFF25D366),
        icon: Icons.chat_rounded,
        title: 'WhatsApp (Meta Cloud API)',
        steps: 'developers.facebook.com → your app → WhatsApp → API Setup: copy the access token, the Phone number ID and the '
            'WhatsApp Business Account ID. Then WhatsApp → Configuration → Webhook: paste the URL and verify token below → Verify and save → '
            'Webhook fields → "messages" → Subscribe. Finally press "Subscribe webhook" here (links your WhatsApp account to the app: '
            'without it Meta never sends messages). Full guide: docs/WHATSAPP_SETUP.md.',
        fields: [
          _field('waToken', 'Access token', secret: true),
          _field('waPhoneId', 'Phone number ID'),
          _field('waBusinessId', 'WhatsApp Business Account ID'),
          _field('waVerifyToken', 'Verify token (any word)'),
        ],
        copy: {'Webhook URL': '$_base/metaWebhook', 'Verify token': _c['waVerifyToken']!.text},
        action: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, spacing: 6, children: [
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _check('wa', () async {
                      final r = await OpsService.testWhatsApp();
                      return '${r.ok ? '✅' : '❌'} ${r.detail}';
                    }),
            child: const Text('Save & test'),
          ),
          FilledButton(
            onPressed: _busy
                ? null
                : () => _check('wa', () async {
                      final r = await OpsService.subscribeWhatsApp(_c['waBusinessId']!.text);
                      if (r.wabaId.isNotEmpty && mounted) setState(() => _c['waBusinessId']!.text = r.wabaId);
                      return '${r.ok ? '✅' : '❌'} ${r.detail}';
                    }),
            child: const Text('Subscribe webhook'),
          ),
        ]),
        status: _status['wa'],
        onCopy: _snack,
      ),
      _Channel(
        color: const Color(0xFF229ED9),
        icon: Icons.send_rounded,
        title: 'Telegram bot (free, judges can use their own phones)',
        steps: 'Open @BotFather in Telegram → /newbot → copy the token here → "Connect". The webhook is set automatically.',
        fields: [_field('telegramBotToken', 'Bot token', secret: true)],
        copy: {'Webhook URL (set for you)': '$_base/telegramWebhook'},
        action: FilledButton(
          onPressed: _busy
              ? null
              : () => _check('tg', () async {
                    final r = await OpsService.testTelegram(setWebhook: true);
                    return '${r.ok ? '✅' : '❌'} ${r.detail}';
                  }),
          child: const Text('Save & connect'),
        ),
        status: _status['tg'],
        onCopy: _snack,
      ),
      _Channel(
        color: const Color(0xFFE1306C),
        icon: Icons.camera_alt_rounded,
        title: 'Instagram DMs',
        steps: 'Needs an Instagram Professional account + the Meta app (Instagram API with Instagram Login). Add the Instagram '
            'product, generate a token, subscribe the same webhook URL to "messages". Until then use Desk → 🧪 Simulate → Instagram, '
            'which goes through exactly the same code.',
        fields: [_field('igToken', 'Instagram access token', secret: true), _field('igUserId', 'Instagram user ID')],
        copy: {'Webhook URL': '$_base/metaWebhook'},
        status: _status['ig'],
        onCopy: _snack,
      ),
      _Channel(
        color: const Color(0xFF4285F4),
        icon: Icons.calendar_month_rounded,
        title: 'Google Calendar (real demo-class bookings)',
        steps: '1) console.cloud.google.com → this Firebase project → enable "Google Calendar API". '
            '2) Google Calendar → your "Demo classes" calendar → Settings → Share with specific people → add the service-account '
            'email shown after "Save & test" with "Make changes to events". 3) Copy the Calendar ID (Settings → Integrate calendar) here.',
        fields: [_field('calendarId', 'Calendar ID (…@group.calendar.google.com)')],
        copy: {if (_serviceAccount.isNotEmpty) 'Share the calendar with': _serviceAccount},
        action: OutlinedButton(
          onPressed: _busy
              ? null
              : () => _check('cal', () async {
                    final r = await OpsService.testCalendar();
                    setState(() => _serviceAccount = r.serviceAccount);
                    return '${r.ok ? '✅' : '❌'} ${r.detail}';
                  }),
          child: const Text('Save & test'),
        ),
        status: _status['cal'],
        onCopy: _snack,
      ),
      _Channel(
        color: const Color(0xFF7248B9),
        icon: Icons.assignment_rounded,
        title: 'Google Forms, Zapier, landing pages (intake webhook)',
        steps: 'In your Google Form: ⋮ → Script editor → paste the script → Triggers → add "onSubmit" → From form → On form submit. '
            'Every submission becomes a lead and Asha follows up.',
        fields: [_field('intakeSecret', 'Shared secret')],
        copy: {
          'Intake URL': '$_base/intakeWebhook',
          'Header x-intake-secret': secret,
          'Apps Script': _appsScript('$_base/intakeWebhook', secret),
        },
        status: null,
        onCopy: _snack,
      ),
      _Channel(
        color: AppTheme.info,
        icon: Icons.phone_in_talk_rounded,
        title: 'Phone calls (Exotel / Twilio / Plivo / Knowlarity)',
        steps: 'Point the provider\'s missed-call or voicemail callback (passthru / status callback) at this URL. The caller\'s number '
            'and any recording become a "call" lead; Asha follows up on WhatsApp and the desk gets a call task. '
            'Demo without a provider: Desk → 🧪 Simulate → Phone call.',
        fields: const [],
        copy: {'Call webhook': '$_base/callWebhook?key=$secret'},
        status: null,
        onCopy: _snack,
      ),
      const SizedBox(height: 4),
      Align(alignment: Alignment.centerLeft, child: FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.save_rounded, size: 18), label: const Text('Save all'))),
    ]);
  }

  Widget _field(String key, String label, {bool secret = false}) => SizedBox(
        width: 330,
        child: TextField(controller: _c[key], obscureText: secret, decoration: InputDecoration(labelText: label, isDense: true)),
      );

  static String _appsScript(String url, String secret) => '''function onSubmit(e) {
  var a = {};
  e.response.getItemResponses().forEach(function (r) { a[r.getItem().getTitle()] = r.getResponse(); });
  var pick = function (re) { for (var k in a) { if (re.test(k)) return String(a[k]); } return ""; };
  UrlFetchApp.fetch("$url", {
    method: "post", contentType: "application/json",
    headers: { "x-intake-secret": "$secret" },
    payload: JSON.stringify({
      source: "googleform",
      name: pick(/name|नाव|नाम/i), phone: pick(/phone|mobile|whatsapp|फोन|मोबाइल/i),
      email: pick(/mail/i), course: pick(/course|कोर्स/i), message: pick(/question|message|query|प्रश्न|सवाल/i),
      extra: a
    })
  });
}''';
}

class _Channel extends StatelessWidget {
  const _Channel({
    required this.color,
    required this.icon,
    required this.title,
    required this.steps,
    required this.fields,
    required this.copy,
    required this.onCopy,
    this.action,
    this.status,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String steps;
  final List<Widget> fields;
  final Map<String, String> copy;
  final Widget? action;
  final String? status;
  final void Function(String) onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.r16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        color: color.withValues(alpha: 0.04),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: context.texts.titleSmall?.copyWith(fontSize: 15))),
          ?action,
        ]),
        const SizedBox(height: 8),
        Text(steps, style: context.texts.bodySmall?.copyWith(fontSize: 12.5, height: 1.5)),
        if (fields.isNotEmpty) ...[const SizedBox(height: 12), Wrap(spacing: 10, runSpacing: 10, children: fields)],
        for (final e in copy.entries)
          if (e.value.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 170, child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
                Expanded(
                  child: SelectableText(
                    e.value.length > 220 ? '${e.value.substring(0, 220)}…' : e.value,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: e.value));
                    onCopy('Copied ${e.key}');
                  },
                ),
              ]),
            ),
        if (status != null) ...[const SizedBox(height: 8), Text(status!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))],
      ]),
    );
  }
}


/// One button that checks everything Asha needs to answer: the message trigger, the database
/// region, the AI keys, the Telegram webhook, the WhatsApp subscription and the last webhook calls.
class _DiagnoseCard extends StatefulWidget {
  const _DiagnoseCard();

  @override
  State<_DiagnoseCard> createState() => _DiagnoseCardState();
}

class _DiagnoseCardState extends State<_DiagnoseCard> {
  bool _running = false;
  String? _error;
  List<Map<String, dynamic>> _checks = const [];

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final c = await OpsService.diagnose();
      if (mounted) setState(() => _checks = c);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.health_and_safety_rounded, color: AppTheme.info),
            const SizedBox(width: 10),
            Expanded(child: Text('Diagnose: why is Asha quiet?', style: context.texts.titleSmall?.copyWith(fontSize: 15))),
            FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: _running
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(_running ? 'Checking…' : 'Run diagnosis'),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'Checks the message trigger, database region, AI keys, the Telegram webhook, the WhatsApp subscription and the last '
            'calls Meta and Telegram actually made to this project (about 20 s).',
            style: context.texts.bodySmall?.copyWith(fontSize: 12.5, height: 1.5),
          ),
          if (_error != null) ...[const SizedBox(height: 8), Text('❌ $_error', style: const TextStyle(fontWeight: FontWeight.w600))],
          for (final c in _checks)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c['ok'] == true ? '✅' : c['ok'] == false ? '❌' : '❔', style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    SelectableText('${c['detail'] ?? ''}', style: const TextStyle(fontSize: 12.5, height: 1.4)),
                    if ((c['fix'] ?? '').toString().isNotEmpty)
                      SelectableText('Fix: ${c['fix']}', style: const TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// The links behind "Talk on WhatsApp", "Talk on Telegram" and the website QR codes.
class _PublicLinksCard extends StatefulWidget {
  const _PublicLinksCard();

  @override
  State<_PublicLinksCard> createState() => _PublicLinksCardState();
}

class _PublicLinksCardState extends State<_PublicLinksCard> {
  late final _wa = TextEditingController(text: PublicLinks.current.value.whatsappNumber);
  late final _waText = TextEditingController(text: PublicLinks.current.value.whatsappText);
  late final _tg = TextEditingController(text: PublicLinks.current.value.telegramBot);
  late final _form = TextEditingController(text: PublicLinks.current.value.formUrl);
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_wa, _waText, _tg, _form]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final l = PublicLinks.from({'whatsappNumber': _wa.text, 'whatsappText': _waText.text, 'telegramBot': _tg.text, 'formUrl': _form.text});
      await PublicLinks.save(l);
      if (mounted) {
        setState(() {
          _wa.text = l.whatsappNumber;
          _tg.text = l.telegramBot;
          _form.text = l.formUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Links saved: website buttons and QR codes updated')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.qr_code_2, color: AppTheme.indigo),
            const SizedBox(width: 10),
            Expanded(child: Text('Public links: website buttons + QR codes', style: context.texts.titleMedium)),
          ]),
          const SizedBox(height: 6),
          Text(
            'What a visitor opens from "Talk on WhatsApp", "Talk on Telegram" and the scan-to-chat QR codes. '
            'WhatsApp must be the number connected to the Cloud API above (with a Meta test number, add each judge\'s '
            'number under API Setup → "To" so Asha\'s replies are delivered).',
            style: context.texts.bodySmall?.copyWith(fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            SizedBox(width: 220, child: TextField(controller: _wa, decoration: const InputDecoration(labelText: 'WhatsApp number (with country code)', hintText: '15551993241', isDense: true))),
            SizedBox(width: 220, child: TextField(controller: _waText, decoration: const InputDecoration(labelText: 'Pre-filled WhatsApp message', isDense: true))),
            SizedBox(width: 220, child: TextField(controller: _tg, decoration: const InputDecoration(labelText: 'Telegram bot (@name or t.me link)', isDense: true))),
            SizedBox(width: 320, child: TextField(controller: _form, decoration: const InputDecoration(labelText: 'Google Form link', isDense: true))),
          ]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save links'),
            ),
          ),
        ]),
      ),
    );
  }
}
