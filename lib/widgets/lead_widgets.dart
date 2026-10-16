import 'package:flutter/material.dart';

import '../app_theme.dart';

const objectionLabels = {
  'fees': '💰 Fees',
  'job_fear': '😟 Job fear',
  'family_approval': '👨‍👩‍👧 Family',
  'time': '⏰ Time',
  'distance': '📍 Distance',
  'language': '🗣 Language',
  'trust': '🤝 Trust',
  'other': '❔ Other',
};

const sourceLabels = {
  'web': '🌐 Web',
  'qr': '🔳 QR',
  'whatsapp': '🟢 WhatsApp',
  'instagram': '📸 Instagram',
  'form': '📝 Form',
  'walkin': '🚶 Walk-in',
  'call': '📞 Call',
};

const statusLabels = {
  'new': 'New',
  'engaged': 'In conversation',
  'demo_booked': 'Demo booked',
  'admitted': 'Admitted',
  'lost': 'Lost',
};

const statusColors = {
  'new': AppTheme.cold,
  'engaged': AppTheme.info,
  'demo_booked': AppTheme.ai,
  'admitted': AppTheme.human,
  'lost': AppTheme.hot,
};

/// Lead score as a ring. The colour carries the temperature, the number the score.
class ScoreBadge extends StatelessWidget {
  const ScoreBadge({super.key, required this.score, required this.temperature, this.big = false});
  final int score;
  final String? temperature;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.temperature(temperature);
    final size = big ? 60.0 : 42.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: (score.clamp(0, 100)) / 100,
              strokeWidth: big ? 5 : 3.5,
              strokeCap: StrokeCap.round,
              color: c,
              backgroundColor: c.withValues(alpha: 0.14),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$score',
                style: TextStyle(fontWeight: FontWeight.w800, color: c, fontSize: big ? 19 : 13.5, height: 1),
              ),
              if (big)
                Text('score',
                    style: TextStyle(fontSize: 9, color: c.withValues(alpha: 0.8), fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class TempChip extends StatelessWidget {
  const TempChip(this.temperature, {super.key});
  final String? temperature;

  @override
  Widget build(BuildContext context) {
    final t = temperature ?? 'cold';
    final c = AppTheme.temperature(t);
    final icon = switch (t) {
      'hot' => '🔥',
      'warm' => '🌤',
      _ => '❄️',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$icon ${t[0].toUpperCase()}${t.substring(1)}',
        style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class SmallChip extends StatelessWidget {
  const SmallChip(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.22)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.scheme.onSurface.withValues(alpha: 0.85)),
      ),
    );
  }
}

/// Status pill with its own colour, used on the lead header.
class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = statusColors[status] ?? AppTheme.cold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(statusLabels[status] ?? status,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
      ]),
    );
  }
}

/// Titled block used down the right-hand insight column.
class InsightCard extends StatelessWidget {
  const InsightCard({super.key, required this.title, required this.child, this.icon, this.accent, this.trailing});
  final String title;
  final Widget child;
  final IconData? icon;
  final Color? accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = accent ?? context.scheme.onSurfaceVariant;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: context.scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.r16),
        border: Border.all(color: accent?.withValues(alpha: 0.3) ?? context.scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 16, color: c), const SizedBox(width: 8)],
            Expanded(
              child: Text(title.toUpperCase(),
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: c)),
            ),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

String initialsOf(String? name) {
  final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  String firstLetter(String s) => String.fromCharCode(s.runes.first);
  final first = firstLetter(parts.first);
  final last = parts.length > 1 ? firstLetter(parts.last) : '';
  return (first + last).toUpperCase();
}
