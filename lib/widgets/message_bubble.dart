import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../utils/ist.dart';

final _calendarLink = RegExp(r'https://calendar\.google\.com\S+');

/// One chat bubble. Shared by the student chat and the counsellor desk —
/// [prospectView] flips the sides and hides the internal labels.
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
    this.imageB64,
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
        imageB64: d['imageB64'] as String?,
      );

  final String role; // user | ai | counsellor | system
  final String text;
  final String? transcript;
  final bool isVoice;
  final DateTime? at;
  final String? channel;
  final Map<String, dynamic> meta;
  final bool prospectView;

  /// A photo the prospect sent (e.g. the payment receipt).
  final String? imageB64;

  @override
  Widget build(BuildContext context) {
    if (role == 'system') return _SystemLine(text: text);

    final fromProspect = role == 'user';
    final alignRight = prospectView ? fromProspect : !fromProspect;
    final automatic = meta['automatic'] == true;
    final guardBlocked = (meta['guard'] as Map?)?['blocked'] == true;
    final scheme = context.scheme;

    late final Color bg;
    late final Color fg;
    if (fromProspect && prospectView) {
      bg = AppTheme.indigo;
      fg = Colors.white;
    } else if (fromProspect) {
      bg = scheme.surfaceContainerHigh;
      fg = scheme.onSurface;
    } else if (role == 'counsellor') {
      bg = AppTheme.human.withValues(alpha: context.isDark ? 0.22 : 0.12);
      fg = scheme.onSurface;
    } else {
      bg = scheme.surface;
      fg = scheme.onSurface;
    }

    final link = _calendarLink.firstMatch(text)?.group(0);
    final shown = link == null ? text : text.replaceAll(link, '').trim();

    String label = '';
    if (!prospectView) {
      if (role == 'ai') {
        if (automatic) {
          label = '✨ Asha · ${_kind(meta['kind'])}${meta['delivered'] == false ? ' · not delivered: ${meta['note'] ?? ''}' : ''}';
        } else {
          final extras = [
            if (meta['kind'] == 'onboarding') '🧾 intake question (${meta['step'] ?? ''})',
            if (meta['cache'] == 'hit') '⚡ instant: same question answered before',
            if (meta['cache'] == 'wait') '⚡ shared one AI call with identical questions',
            if (meta['answeredTogether'] != null) 'answered ${meta['answeredTogether']} messages together',
            if (meta['offline'] == true) '📚 AI unavailable: answered from the knowledge base, auto-retrying'
            else if (meta['fallback'] == true) 'AI busy: auto-retrying',
            if (meta['delivered'] == false) '⚠️ not delivered: ${meta['note'] ?? ''}',
          ];
          label = extras.isEmpty ? '✨ Asha (AI)' : '✨ Asha · ${extras.join(' · ')}';
        }
      }
      if (role == 'counsellor') label = '🧑 ${meta['by'] ?? 'Counsellor'}';
      if (role == 'user') label = _channelLabel(channel);
    } else if (role == 'counsellor') {
      label = '${meta['by'] ?? 'Counsellor'} · SechTummit Trainers';
    }

    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(alignRight ? 18 : 5),
              bottomRight: Radius.circular(alignRight ? 5 : 18),
            ),
            border: guardBlocked && !prospectView
                ? Border.all(color: AppTheme.guard.withValues(alpha: 0.5), width: 1.2)
                : (role == 'ai' && !prospectView) || (role == 'ai' && prospectView)
                    ? Border.all(color: context.scheme.outlineVariant)
                    : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: fg.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              if (imageB64 != null) _Photo(b64: imageB64!),
              if (isVoice)
                _VoiceRow(label: shown.isEmpty ? 'Voice note' : shown, color: fg)
              else
                SelectableText(shown, style: TextStyle(color: fg, height: 1.45, fontSize: 14.5)),
              if (isVoice && transcript != null && transcript!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('“$transcript”',
                      style: TextStyle(color: fg.withValues(alpha: 0.92), height: 1.45, fontSize: 14)),
                ),
              if (link != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.event_available, size: 17),
                    label: const Text('Add to Google Calendar'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      backgroundColor: prospectView ? Colors.white : AppTheme.indigo,
                      foregroundColor: prospectView ? AppTheme.indigoDeep : Colors.white,
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
                  ),
                ),
              if (guardBlocked && !prospectView) _GuardNote(meta: meta),
              const SizedBox(height: 3),
              Text(
                at == null ? 'sending…' : Ist.time(at!),
                style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.55)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _kind(Object? k) => switch (k) {
        'reminder_24h' => 'reminder, 24 h before',
        'reminder_1h' => 'reminder, 1 h before',
        'followup' => 'automatic follow-up',
        'session_closed' => 'chat closed after 2 min of silence',
        'enrollment_verified' => 'payment verified, course allotted',
        'enrollment_rejected' => 'payment not verified',
        'call_reminder_24h' => 'call reminder, 24 h before',
        'call_reminder_1h' => 'call reminder, 1 h before',
        'language' => 'language question',
        _ => 'automatic',
      };

  static String _channelLabel(String? c) => switch (c) {
        'whatsapp' => '🟢 WhatsApp',
        'telegram' => '✈️ Telegram',
        'googleform' => '🧾 Google Form',
        'form' => '📝 Website form',
        'walkin' => '🚶 Walk-in',
        'call' => '📞 Call',
        'instagram' => '📸 Instagram',
        _ => '🌐 Web chat',
      };
}

class _Photo extends StatelessWidget {
  const _Photo({required this.b64});
  final String b64;

  @override
  Widget build(BuildContext context) {
    final bytes = base64Decode(b64);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (c) => Dialog(
            child: InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain)),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 260),
            child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
          ),
        ),
      ),
    );
  }
}

class _VoiceRow extends StatelessWidget {
  const _VoiceRow({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // A static waveform: enough to read as audio without pretending to play it.
    const bars = [6.0, 11.0, 17.0, 9.0, 14.0, 20.0, 8.0, 13.0, 7.0, 16.0, 10.0, 5.0];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.graphic_eq_rounded, size: 18, color: color.withValues(alpha: 0.9)),
        const SizedBox(width: 8),
        for (final b in bars)
          Container(
            width: 2.5,
            height: b,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(label,
              style: TextStyle(color: color.withValues(alpha: 0.9), fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _SystemLine extends StatelessWidget {
  const _SystemLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Expanded(child: Divider(color: context.scheme.outlineVariant)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(text,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.scheme.onSurfaceVariant)),
          ),
          Expanded(child: Divider(color: context.scheme.outlineVariant)),
        ]),
      );
}

class _GuardNote extends StatelessWidget {
  const _GuardNote({required this.meta});
  final Map<String, dynamic> meta;

  @override
  Widget build(BuildContext context) {
    final draft = (meta['guard'] as Map?)?['draft'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.shield_rounded, color: AppTheme.guard, size: 32),
            title: const Text('Guard blocked the first draft'),
            content: Text(
              'The AI\'s first draft contained something that is not in the institute\'s knowledge base, '
              'so it was rewritten before anything was sent:\n\n“$draft”',
              style: const TextStyle(height: 1.5),
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Got it'))],
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.guard.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.shield_rounded, size: 14, color: AppTheme.guard),
            SizedBox(width: 6),
            Text('Guard rewrote an invented claim — tap to see',
                style: TextStyle(fontSize: 11, color: AppTheme.guard, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.scheme.surface,
          border: Border.all(color: context.scheme.outlineVariant),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(5),
          ),
        ),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5),
                  child: Opacity(
                    opacity: 0.35 + 0.65 * ((((_c.value * 3) - i) % 3).clamp(0.0, 1.0)),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(color: AppTheme.indigo, shape: BoxShape.circle),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              Text('Asha is typing…', style: context.texts.bodySmall?.copyWith(fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}
