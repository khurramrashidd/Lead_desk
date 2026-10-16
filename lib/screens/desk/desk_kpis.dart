import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../services/repo.dart';
import '../../utils/ist.dart';

/// The numbers a counsellor should see before anything else.
class KpiStrip extends StatelessWidget {
  const KpiStrip({super.key, required this.leads, this.compact = false});

  final List<Map<String, dynamic>> leads;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hot = leads.where((l) => l['temperature'] == 'hot').length;
    final needsYou = leads.where((l) => l['needsHuman'] == true || l['possibleDuplicateOf'] != null).length;
    final overdue = leads.where((l) {
      final na = l['nextAction'] as Map?;
      final at = Ist.fromTimestamp(na?['at']);
      return na != null && na['done'] != true && at != null && at.isBefore(now);
    }).length;
    final demos = leads.where((l) {
      final at = Ist.fromTimestamp((l['booking'] as Map?)?['startAt']);
      return at != null && at.isAfter(now) && at.difference(now).inHours < 48;
    }).length;
    final admitted = leads.where((l) => l['status'] == 'admitted').length;

    final tiles = <Widget>[
      _Kpi(label: 'Open leads', value: '${leads.length}', icon: Icons.inbox_rounded, color: AppTheme.indigo),
      _Kpi(label: 'Hot right now', value: '$hot', icon: Icons.local_fire_department_rounded, color: AppTheme.hot),
      _Kpi(label: 'Need you', value: '$needsYou', icon: Icons.pan_tool_rounded, color: AppTheme.warm, pulse: needsYou > 0),
      _Kpi(label: 'Follow-ups due', value: '$overdue', icon: Icons.schedule_rounded, color: AppTheme.info),
      _Kpi(label: 'Demos in 48 h', value: '$demos', icon: Icons.event_available_rounded, color: AppTheme.ai),
      _Kpi(label: 'Admitted', value: '$admitted', icon: Icons.school_rounded, color: AppTheme.human),
    ];

    return LayoutBuilder(builder: (context, c) {
      final perRow = (c.maxWidth / (compact ? 150 : 185)).floor().clamp(2, 6);
      final width = (c.maxWidth - 12 * (perRow - 1)) / perRow;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [for (final t in tiles.take(perRow == 2 ? 4 : 6)) SizedBox(width: width, child: t)],
      );
    });
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, required this.icon, required this.color, this.pulse = false});
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: context.scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.r16),
        border: Border.all(color: pulse ? color.withValues(alpha: 0.5) : context.scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, size: 16, color: color),
            ),
            const Spacer(),
            Text(value,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -1, color: context.scheme.onSurface)),
          ]),
          const SizedBox(height: 6),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Streams the lead list once and hands it to [KpiStrip].
class LiveKpiStrip extends StatelessWidget {
  const LiveKpiStrip({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: Repo.watchLeads(),
      builder: (context, snap) {
        final leads = (snap.data ?? []).map((d) => d.data()).toList();
        return KpiStrip(leads: leads, compact: compact);
      },
    );
  }
}
