import 'package:flutter/material.dart';

import '../app_theme.dart';

const objectionLabels = {
  'fees': '💰 Fees',
  'job_fear': '😟 Job fear',
  'family_approval': '👨‍👩‍👧 Family approval',
  'time': '⏰ Time',
  'distance': '📍 Distance',
  'language': '🗣 Language',
  'trust': '🤝 Trust',
  'other': '❔ Other',
};

const sourceLabels = {
  'web': '🌐 Web chat',
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

class ScoreBadge extends StatelessWidget {
  const ScoreBadge({super.key, required this.score, required this.temperature, this.big = false});
  final int score;
  final String? temperature;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.temperature(temperature);
    final size = big ? 56.0 : 40.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(
          value: score / 100,
          strokeWidth: big ? 5 : 3.5,
          color: c,
          backgroundColor: c.withValues(alpha: 0.15),
        ),
        Text('$score', style: TextStyle(fontWeight: FontWeight.w800, color: c, fontSize: big ? 18 : 13)),
      ]),
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
    final icon = t == 'hot' ? '🔥' : (t == 'warm' ? '🌤' : '❄️');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text('$icon ${t[0].toUpperCase()}${t.substring(1)}', style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class SmallChip extends StatelessWidget {
  const SmallChip(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Text(text, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurface)),
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
