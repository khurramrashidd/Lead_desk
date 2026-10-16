import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_theme.dart';
import '../../config.dart';
import '../../services/ops_service.dart';

/// Admin → Channels. Every place an enquiry can come from, in one screen,
/// with a "test" button for each so nothing is a surprise during judging.
class ChannelsPanel extends StatefulWidget {
  const ChannelsPanel({super.key});

  @override
  State<ChannelsPanel> createState() => _ChannelsPanelState();
}

class _ChannelsPanelState extends State<ChannelsPanel> {
  final _waToken = TextEditingController();
  final _waPhoneId = TextEditingController();
  final _tgToken = TextEditingController();
  final _igHandle = TextEditingController();
  final _functionsBase = TextEditingController();

  bool _loaded = false;
  bool _busy = false;
  String? _waResult;
  String? _tgResult;

  @override
  void initState() {
    super.initState();
    OpsService.channelsDoc.get().then((snap) {
      final d = snap.data() ?? {};
      if (!mounted) return;
      setState(() {
        _waToken.text = d['waToken'] as String? ?? '';
        _waPhoneId.text = d['waPhoneId'] as String? ?? '';
        _tgToken.text = d['telegramBotToken'] as String? ?? '';
        _igHandle.text = d['instagramHandle'] as String? ?? '';
        _functionsBase.text = d['functionsBase'] as String? ?? kFunctionsBase;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    for (final c in [_waToken, _waPhoneId, _tgToken, _igHandle, _functionsBase]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String m, {bool bad = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: bad ? context.scheme.error : null,
      duration: Duration(seconds: bad ? 8 : 4),
    ));
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await OpsService.saveChannels({
        'waToken': _waToken.text.trim(),
        'waPhoneId': _waPhoneId.text.trim(),
        'telegramBotToken': _tgToken.text.trim(),
        'instagramHandle': _igHandle.text.trim().replaceAll('@', ''),
        'functionsBase': _functionsBase.text.trim(),
      });
      _snack('Saved. The AI picks this up within 30 seconds — no redeploy needed.');
    } catch (e) {
      _snack('Could not save: $e', bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fnUrl(String name) {
    final base = _functionsBase.text.trim().replaceAll(RegExp(r'/+$'), '');
    return base.isEmpty ? '(set the functions base URL below)' : '$base/$name';
  }

  Future<void> _testWhatsApp() async {
    setState(() {
      _busy = true;
      _waResult = null;
    });
    try {
      await _save();
      final r = await OpsService.testWhatsApp();
      setState(() => _waResult = r.ok ? '✅ ${r.detail}' : '❌ ${r.detail}');
    } catch (e) {
      setState(() => _waResult = '❌ $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testTelegram({bool setWebhook = false}) async {
    setState(() {
      _busy = true;
      _tgResult = null;
    });
    try {
      await _save();
      final r = await OpsService.testTelegram(webhookUrl: setWebhook ? _fnUrl('telegramWebhook') : null);
      setState(() => _tgResult = r.ok ? '✅ ${r.detail}' : '❌ ${r.detail}');
    } catch (e) {
      setState(() => _tgResult = '❌ $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Padding(padding: EdgeInsets.all(20), child: LinearProgressIndicator(minHeight: 3));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_busy) const Padding(padding: EdgeInsets.only(bottom: 10), child: LinearProgressIndicator(minHeight: 3)),

        _Channel(
          emoji: '🟢',
          name: 'WhatsApp',
          colour: const Color(0xFF25D366),
          status: _waToken.text.isEmpty ? 'Not connected' : 'Configured',
          children: [
            TextField(
              controller: _waToken,
              decoration: const InputDecoration(
                labelText: 'Access token',
                helperText: 'Meta → WhatsApp → API Setup. Use a system-user token so it does not expire mid-demo.',
                helperMaxLines: 3,
              ),
              maxLines: 1,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _waPhoneId,
              decoration: const InputDecoration(
                labelText: 'Phone number ID',
                helperText: 'The numeric ID under "From", not the phone number itself.',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            _CopyRow(label: 'Webhook callback URL', value: _fnUrl('whatsappWebhook'), onCopy: _snack),
            _CopyRow(label: 'Verify token', value: kVerifyTokenHint, onCopy: _snack),
            const SizedBox(height: 12),
            Row(children: [
              FilledButton.icon(
                onPressed: _busy ? null : _testWhatsApp,
                icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
                label: const Text('Save and test connection'),
              ),
            ]),
            if (_waResult != null) _Result(_waResult!),
          ],
        ),

        _Channel(
          emoji: '✈️',
          name: 'Telegram',
          colour: const Color(0xFF229ED9),
          status: _tgToken.text.isEmpty ? 'Not connected' : 'Configured',
          children: [
            Text(
              'Open @BotFather in Telegram → /newbot → copy the token here → press "Connect webhook". '
              'That is the whole setup, and it is free.',
              style: context.texts.bodySmall?.copyWith(fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tgToken,
              decoration: const InputDecoration(labelText: 'Bot token', hintText: '1234567:AA…'),
              maxLines: 1,
            ),
            const SizedBox(height: 12),
            _CopyRow(label: 'Webhook URL', value: _fnUrl('telegramWebhook'), onCopy: _snack),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _testTelegram(setWebhook: true),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Connect webhook'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _testTelegram(),
                icon: const Icon(Icons.bolt_rounded, size: 18),
                label: const Text('Test only'),
              ),
            ]),
            if (_tgResult != null) _Result(_tgResult!),
          ],
        ),

        _Channel(
          emoji: '📸',
          name: 'Instagram',
          colour: const Color(0xFFD62976),
          status: _igHandle.text.isEmpty ? 'Bio link only' : '@${_igHandle.text.trim()}',
          children: [
            TextField(
              controller: _igHandle,
              decoration: const InputDecoration(labelText: 'Instagram handle', hintText: 'sechtummit'),
            ),
            const SizedBox(height: 12),
            _CopyRow(label: 'Put this in your Instagram bio', value: chatLink('instagram'), onCopy: _snack),
            const SizedBox(height: 10),
            Text(
              'Every lead that arrives through that link is tagged "Instagram", so the reports can tell you '
              'whether Instagram actually produces admissions.\n\n'
              'Real IG direct messages need a Business account linked to this Meta app and Meta\'s review of '
              'instagram_manage_messages. Once that is approved the same webhook above already handles them — '
              'nothing to change here. Until then, counsellors paste a DM into a lead with '
              '"Log an Instagram DM" on the desk, and Asha drafts the reply.',
              style: context.texts.bodySmall?.copyWith(fontSize: 12.5, height: 1.55),
            ),
          ],
        ),

        _Channel(
          emoji: '📝',
          name: 'Google Form, IVR and anything else',
          colour: AppTheme.info,
          status: 'One endpoint',
          children: [
            Text(
              'Any system that can send an HTTP request becomes a channel: a Google Form, a telephony/IVR '
              'provider, Zapier, or your old website.',
              style: context.texts.bodySmall?.copyWith(fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 12),
            _CopyRow(label: 'Intake endpoint', value: _fnUrl('intakeWebhook'), onCopy: _snack),
            _CopyRow(label: 'Shared secret (header x-intake-secret)', value: kIntakeSecretHint, onCopy: _snack),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _showAppsScript(context),
              icon: const Icon(Icons.code_rounded, size: 18),
              label: const Text('Google Form script (copy & paste)'),
            ),
          ],
        ),

        _Channel(
          emoji: '🏢',
          name: 'At the counter',
          colour: AppTheme.human,
          status: 'Built in',
          children: [
            Text(
              'Walk-ins are captured on the Walk-in screen with the branch location and IST time. '
              'A phone call taken at the desk is logged from any lead with "Log a phone call" — '
              'Asha then drafts the follow-up exactly as it would for a chat.',
              style: context.texts.bodySmall?.copyWith(fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 10, children: [
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pushNamed('/walkin'),
                icon: const Icon(Icons.storefront_outlined, size: 18),
                label: const Text('Open walk-in entry'),
              ),
            ]),
          ],
        ),

        const SizedBox(height: 6),
        TextField(
          controller: _functionsBase,
          decoration: const InputDecoration(
            labelText: 'Cloud Functions base URL',
            helperText: 'Printed by deploy, e.g. https://asia-south1-your-project.cloudfunctions.net',
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_rounded, size: 18),
            label: const Text('Save all channel settings'),
          ),
        ),
      ],
    );
  }

  void _showAppsScript(BuildContext context) {
    final script = '''
// Google Form → AI Lead Desk
// 1. Open your Form → ⋮ → Script editor
// 2. Paste this, set the two values below, Save
// 3. Triggers (clock icon) → Add Trigger → onSubmit → From form → On form submit
const ENDPOINT = '${_fnUrl('intakeWebhook')}';
const SECRET   = '$kIntakeSecretHint';

function onSubmit(e) {
  const answers = {};
  e.response.getItemResponses().forEach(function (r) {
    answers[r.getItem().getTitle()] = r.getResponse();
  });
  // Rename these to match your own question titles
  const payload = {
    secret: SECRET,
    source: 'googleform',
    name:    answers['Name'] || answers['Full name'] || '',
    phone:   answers['Mobile'] || answers['Phone'] || '',
    email:   answers['Email'] || '',
    course:  answers['Course'] || '',
    message: answers['Your question'] || answers['Message'] || '',
    relation: answers['Who is this for?'] || 'self',
    extra: answers,
  };
  UrlFetchApp.fetch(ENDPOINT, {
    method: 'post',
    contentType: 'application/json',
    payload: JSON.stringify(payload),
    muteHttpExceptions: true,
  });
}''';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Google Form → AI Lead Desk'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111322),
                borderRadius: BorderRadius.circular(AppTheme.r12),
              ),
              child: SelectableText(
                script,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.5, color: Color(0xFFE2E8F0)),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 17),
            label: const Text('Copy script'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: script));
              Navigator.pop(ctx);
              _snack('Script copied — paste it into the Form\'s Script editor.');
            },
          ),
        ],
      ),
    );
  }
}

class _Channel extends StatelessWidget {
  const _Channel({
    required this.emoji,
    required this.name,
    required this.colour,
    required this.status,
    required this.children,
  });

  final String emoji;
  final String name;
  final Color colour;
  final String status;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: context.scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.r16),
        border: Border.all(color: context.scheme.outlineVariant),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          leading: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colour.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 18)),
          ),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          subtitle: Text(status, style: context.texts.bodySmall?.copyWith(fontSize: 12)),
          children: children,
        ),
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value, required this.onCopy});
  final String label;
  final String value;
  final void Function(String) onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.scheme.onSurfaceVariant)),
          const SizedBox(height: 3),
          Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: context.scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppTheme.r8),
                ),
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5)),
              ),
            ),
            IconButton(
              tooltip: 'Copy',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_rounded, size: 17),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                onCopy('Copied');
              },
            ),
          ]),
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final ok = text.startsWith('✅');
    final c = ok ? AppTheme.human : AppTheme.hot;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppTheme.r12),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: TextStyle(fontSize: 12.8, height: 1.5, color: context.scheme.onSurface)),
    );
  }
}
