import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../services/repo.dart';
import '../../widgets/lead_widgets.dart';

/// "Where do our admissions really come from?" Conversion by source, counsellor and objection.
class ReportsView extends StatelessWidget {
  const ReportsView({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: Repo.watchLeads(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final leads = snap.data!.map((d) => d.data()).toList();
        final total = leads.length;
        final admitted = leads.where((l) => l['status'] == 'admitted').length;
        final booked = leads.where((l) => l['status'] == 'demo_booked' || l['booking'] != null).length;
        final hot = leads.where((l) => l['temperature'] == 'hot').length;

        final bySource = _group(leads, (l) => [(l['firstSource'] as String?) ?? 'web']);
        final byCounsellor = _group(leads, (l) => [(l['assignedTo'] as String?) ?? 'AI only']);
        final byObjection = _group(leads, (l) => ((l['objections'] as List?)?.cast<String>() ?? const <String>[]));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(spacing: 10, runSpacing: 10, children: [
              _Kpi('Leads', '$total', Icons.people),
              _Kpi('Hot', '$hot', Icons.local_fire_department),
              _Kpi('Demos booked', '$booked', Icons.event_available),
              _Kpi('Admitted', '$admitted', Icons.school),
              _Kpi('Conversion', total == 0 ? '-' : '${(admitted * 100 / total).toStringAsFixed(0)}%', Icons.trending_up),
            ]),
            const SizedBox(height: 16),
            _Section('Conversion by source', bySource, labels: sourceLabels),
            _Section('Conversion by counsellor', byCounsellor),
            _Section('Objections raised (and how many still admitted)', byObjection, labels: objectionLabels),
          ],
        );
      },
    );
  }

  Map<String, (int, int)> _group(List<Map<String, dynamic>> leads, List<String> Function(Map<String, dynamic>) keys) {
    final out = <String, (int, int)>{};
    for (final l in leads) {
      for (final k in keys(l)) {
        final (n, a) = out[k] ?? (0, 0);
        out[k] = (n + 1, a + (l['status'] == 'admitted' ? 1 : 0));
      }
    }
    return out;
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: scheme.primary),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.data, {this.labels = const {}});
  final String title;
  final Map<String, (int, int)> data;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = data.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    final max = rows.isEmpty ? 1 : rows.first.value.$1;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          Text('Bar = leads · green part = admitted', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          if (rows.isEmpty) const Text('No data yet'),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(width: 140, child: Text(labels[r.key] ?? r.key, overflow: TextOverflow.ellipsis)),
                Expanded(
                  child: LayoutBuilder(builder: (context, c) {
                    final w = c.maxWidth * r.value.$1 / max;
                    final wa = r.value.$1 == 0 ? 0.0 : w * r.value.$2 / r.value.$1;
                    return Stack(children: [
                      Container(height: 18, width: w, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(6))),
                      Container(height: 18, width: wa, decoration: BoxDecoration(color: AppTheme.human, borderRadius: BorderRadius.circular(6))),
                    ]);
                  }),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 92,
                  child: Text(
                    '${r.value.$1} · ${r.value.$2} adm (${r.value.$1 == 0 ? 0 : (r.value.$2 * 100 / r.value.$1).round()}%)',
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.right,
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
