import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Everything in the app is shown in Indian Standard Time, whatever the device's time zone.
class Ist {
  static const _offset = Duration(hours: 5, minutes: 30);

  /// A DateTime whose fields read as IST wall-clock time (use only for formatting).
  static DateTime toIst(DateTime d) => d.toUtc().add(_offset);

  static DateTime now() => toIst(DateTime.now());

  static DateTime? fromTimestamp(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  /// "Fri, 16 Oct · 2:23 PM IST"
  static String full(DateTime d) => '${DateFormat('EEE, d MMM · h:mm a').format(toIst(d))} IST';

  /// "2:23 PM"
  static String time(DateTime d) => DateFormat('h:mm a').format(toIst(d));

  /// "just now", "5 min ago", "3 h ago", "Yesterday", "12 Oct"
  static String relative(DateTime? d) {
    if (d == null) return 'now';
    final diff = DateTime.now().difference(d);
    if (diff.isNegative) return 'in ${_span(diff.abs())}';
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return DateFormat('d MMM').format(toIst(d));
  }

  static String _span(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inHours < 24) return '${d.inHours} h';
    return '${d.inDays} d';
  }
}

/// Live IST clock for app bars: "Fri 16 Oct · 3:45:12 PM IST"
class IstClock extends StatefulWidget {
  const IstClock({super.key, this.compact = false});
  final bool compact;

  @override
  State<IstClock> createState() => _IstClockState();
}

class _IstClockState extends State<IstClock> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = Ist.now();
    final text = widget.compact
        ? '${DateFormat('h:mm a').format(now)} IST'
        : '${DateFormat('EEE d MMM · h:mm:ss a').format(now)} IST';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.schedule, size: 16),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
