import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../data/links.dart';
import '../l10n.dart';

/// Brand-neutral colours for the two messaging apps (no logos are drawn).
class ChannelColors {
  static const whatsapp = Color(0xFF1FAF55);
  static const telegram = Color(0xFF2A9BD8);
  static const form = Color(0xFF7A4FD6);
}

enum ChatChannel { whatsapp, telegram, form }

extension ChatChannelX on ChatChannel {
  Color get color => switch (this) {
        ChatChannel.whatsapp => ChannelColors.whatsapp,
        ChatChannel.telegram => ChannelColors.telegram,
        ChatChannel.form => ChannelColors.form,
      };

  IconData get icon => switch (this) {
        ChatChannel.whatsapp => Icons.chat_rounded,
        ChatChannel.telegram => Icons.send_rounded,
        ChatChannel.form => Icons.assignment_outlined,
      };

  String get title => switch (this) {
        ChatChannel.whatsapp => 'WhatsApp',
        ChatChannel.telegram => 'Telegram',
        ChatChannel.form => tr('qr.form'),
      };

  String get talkLabel => switch (this) {
        ChatChannel.whatsapp => tr('talk.whatsapp'),
        ChatChannel.telegram => tr('talk.telegram'),
        ChatChannel.form => tr('qr.formOpen'),
      };

  String url(PublicLinks l) => switch (this) {
        ChatChannel.whatsapp => l.whatsappUrl,
        ChatChannel.telegram => l.telegramUrl,
        ChatChannel.form => l.formUrl,
      };

  String handle(PublicLinks l) => switch (this) {
        ChatChannel.whatsapp => l.whatsappDisplay,
        ChatChannel.telegram => '@${l.telegramBot}',
        ChatChannel.form => 'forms.gle',
      };
}

/// Opens WhatsApp / Telegram / the form (the app itself on a phone, a new tab on a laptop).
Future<void> openChannel(BuildContext context, ChatChannel c) async {
  final url = c.url(PublicLinks.current.value);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) messenger?.showSnackBar(SnackBar(content: Text('Could not open $url')));
  } catch (_) {
    messenger?.showSnackBar(SnackBar(content: Text('Could not open $url')));
  }
}

/// "Talk on WhatsApp" / "Talk on Telegram" button.
class TalkButton extends StatelessWidget {
  const TalkButton(this.channel, {super.key, this.compact = false, this.expand = false});
  final ChatChannel channel;
  final bool compact;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final b = FilledButton.icon(
      onPressed: () => openChannel(context, channel),
      icon: Icon(channel.icon, size: compact ? 16 : 18),
      label: Text(compact ? channel.title : channel.talkLabel, overflow: TextOverflow.ellipsis),
      style: FilledButton.styleFrom(
        backgroundColor: channel.color,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20, vertical: compact ? 12 : 16),
        minimumSize: expand ? const Size.fromHeight(50) : null,
      ),
    );
    return b;
  }
}

/// One scan-to-chat card: a QR code that opens WhatsApp, Telegram or the Google Form.
class ChannelQrCard extends StatelessWidget {
  const ChannelQrCard(this.channel, {super.key, this.qrSize = 150});
  final ChatChannel channel;
  final double qrSize;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PublicLinks>(
      valueListenable: PublicLinks.current,
      builder: (context, links, _) {
        final url = channel.url(links);
        return Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          decoration: BoxDecoration(
            color: context.scheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.r20),
            border: Border.all(color: channel.color.withValues(alpha: 0.35)),
            boxShadow: AppTheme.lift(context, y: 6, blur: 22, opacity: 0.05),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: channel.color, borderRadius: BorderRadius.circular(10)),
                child: Icon(channel.icon, color: Colors.white, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(channel.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                  Text(channel.handle(links), style: context.texts.bodySmall?.copyWith(fontSize: 12), overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppTheme.r12)),
              child: QrImageView(
                data: url,
                size: qrSize,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0B1220)),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF0B1220)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              switch (channel) {
                ChatChannel.whatsapp => tr('qr.wa.sub'),
                ChatChannel.telegram => tr('qr.tg.sub'),
                ChatChannel.form => tr('qr.form.sub'),
              },
              textAlign: TextAlign.center,
              style: context.texts.bodySmall?.copyWith(fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => openChannel(context, channel),
                icon: Icon(Icons.open_in_new_rounded, size: 16, color: channel.color),
                label: Text(channel == ChatChannel.form ? tr('qr.formOpen') : '${tr('qr.open')} ${channel.title}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: channel.color,
                  side: BorderSide(color: channel.color.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

/// A bottom sheet with the WhatsApp / Telegram / form options (used in the chat header).
Future<void> showOtherChannelsSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('talk.title'), style: context.texts.titleLarge),
            const SizedBox(height: 4),
            Text(tr('talk.sub'), style: context.texts.bodySmall),
            const SizedBox(height: 16),
            const TalkButton(ChatChannel.whatsapp, expand: true),
            const SizedBox(height: 10),
            const TalkButton(ChatChannel.telegram, expand: true),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => openChannel(context, ChatChannel.form),
              icon: const Icon(Icons.assignment_outlined, size: 18),
              label: Text(tr('qr.formOpen')),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            ),
          ]),
        ),
      ),
    );
