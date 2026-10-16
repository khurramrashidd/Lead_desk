import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../utils/ist.dart';

final _calendarLink = RegExp(r'https://calendar\.google\.com\S+');

/// One chat bubble. Used in the student chat and the counsellor desk.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.role,
    this.text = '',
    this.transcript,
    this.isVoice = false,
    this.at,
    this.channel,
    this.meta = const {},
    this.prospectView = false,
  });

  factory MessageBubble.fromDoc(Map<String, dynamic> d, {bool prospectView = false}) => MessageBubble(
        role: d['role'] as String? ?? 'user',
        text: d['text'] as String? ?? '',
        transcript: d['transcript'] as String?,
        isVoice: d['audioB64'] != null,
        at: Ist.fromTimestamp(d['createdAt']),
        channel: d['channel'] as String?,
        meta: (d['meta'] as Map?)?.cast<String, dynamic>() ?? const {},
        prospectView: prospectView,
      );

  final String role; // user | ai | counsellor | system
  final String text;
  final String? transcript;
  final bool isVoice;
  final DateTime? at;
  final String? channel;
  final Map<String, dynamic> meta;
  final bool prospectView; // true = student's screen (their messages on the right)

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (role == 'system') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text('— $text —', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ),
      );
    }

    final fromProspect = role == 'user';
    final alignRight = prospectView ? fromProspect : !fromProspect;
    final automatic = meta['automatic'] == true;
    final guardBlocked = (meta['guard'] as Map?)?['blocked'] == true;

    Color bg;
    Color fg;
    if (fromProspect) {
      bg = prospectView ? scheme.primary : scheme.surfaceContainerHighest;
      fg = prospectView ? scheme.onPrimary : scheme.onSurface;
    } else if (role == 'counsellor') {
      bg = AppTheme.human.withValues(alpha: 0.15);
      fg = scheme.onSurface;
    } else {
      bg = prospectView ? scheme.surfaceContainerHighest : AppTheme.ai.withValues(alpha: 0.13);
      fg = scheme.onSurface;
    }

    final link = _calendarLink.firstMatch(text)?.group(0);
    final shown = link == null ? text : text.replaceAll(link, '').trim();

    String label = '';
    if (!prospectView) {
      if (role == 'ai') label = automatic ? '🤖 Asha · ${_kind(meta['kind'])}' : '🤖 Asha (AI)';
      if (role == 'counsellor') label = '🧑 ${meta['by'] ?? 'Counsellor'}';
      if (role == 'user') label = '${_channelEmoji(channel)} Prospect';
    } else if (role == 'counsellor') {
      label = '${meta['by'] ?? 'Counsellor'} · TechSummitTrainers';
    }

    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(alignRight ? 16 : 4),
              bottomRight: Radius.circular(alignRight ? 4 : 16),
            ),
            border: guardBlocked && !prospectView ? Border.all(color: AppTheme.guard, width: 1.2) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.7))),
                ),
              if (isVoice)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.graphic_eq, size: 18, color: fg),
                  const SizedBox(width: 6),
                  Flexible(child: Text(shown.isEmpty ? 'Voice note' : shown, style: TextStyle(color: fg, fontStyle: FontStyle.italic))),
                ])
              else
                SelectableText(shown, style: TextStyle(color: fg, height: 1.35)),
              if (isVoice && transcript != null && transcript!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('“$transcript”', style: TextStyle(color: fg, height: 1.35)),
                ),
              if (link != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.event_available, size: 18),
                    label: const Text('Add to Google Calendar'),
                    onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
                  ),
                ),
              if (guardBlocked && !prospectView) _GuardNote(meta: meta),
              const SizedBox(height: 2),
              Text(at == null ? 'sending…' : Ist.time(at!),
                  style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.6))),
            ],
          ),
        ),
      ),
    );
  }

  static String _kind(Object? k) {
    switch (k) {
      case 'reminder_24h':
        return 'reminder (24 h)';
      case 'reminder_1h':
        return 'reminder (1 h)';
      case 'followup':
        return 'auto follow-up';
      default:
        return 'automatic';
    }
  }

  static String _channelEmoji(String? c) {
    switch (c) {
      case 'whatsapp':
        return '🟢 WhatsApp';
      case 'form':
        return '📝 Form';
      case 'walkin':
        return '🚶 Walk-in';
      case 'call':
        return '📞 Call';
      case 'instagram':
        return '📸 Instagram';
      default:
        return '🌐 Web';
    }
  }
}

class _GuardNote extends StatelessWidget {
  const _GuardNote({required this.meta});
  final Map<String, dynamic> meta;

  @override
  Widget build(BuildContext context) {
    final draft = (meta['guard'] as Map?)?['draft'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('🛡 Guard blocked the first draft'),
            content: Text('The AI\'s first draft contained something not in the knowledge base, so it was rewritten before sending:\n\n“$draft”'),
            actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('OK'))],
          ),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.shield, size: 16, color: AppTheme.guard),
          SizedBox(width: 4),
          Text('Guard rewrote an invented claim · tap', style: TextStyle(fontSize: 11, color: AppTheme.guard, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Asha is typing…'),
        ]),
      ),
    );
  }
}
