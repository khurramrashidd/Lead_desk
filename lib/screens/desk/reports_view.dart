import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../services/repo.dart';
import '../../widgets/lead_widgets.dart';
import '../auth/auth_gate.dart';
import 'desk_kpis.dart';

/// "Where do our admissions really come from?" — conversion by source,
/// by counsellor and by the objection the prospect raised.
class ReportsView extends StatelessWidget {
  const ReportsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.scheme.surfaceContainerLow,
      child: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: Repo.watchLeads(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          // Load-test leads are excluded from conversion numbers.
          final leads = snap.data!.map((d) => d.data()).where((l) => l['burst'] != true).toList();

          final bySource = _group(leads, (l) => [(l['firstSource'] as String?) ?? 'web']);
          final byCounsellor = _group(leads, (l) => [(l['assignedTo'] as String?) ?? 'Asha only']);
          final byObjection = _group(leads, (l) => (l['objections'] as List?)?.cast<String>() ?? const <String>[]);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
            children: [
              KpiStrip(leads: leads),
              const SizedBox(height: 24),
              const _ScaleCard(),
              _Chart(title: 'Conversion by source', subtitle: 'Which channel actually produces admissions', data: bySource, labels: sourceLabels),
              _Chart(title: 'Conversion by counsellor', subtitle: 'Who is converting the leads they are given', data: byCounsellor),
              _Chart(
                title: 'Objections raised',
                subtitle: 'What stops people — and how many still joined',
                data: byObjection,
                labels: objectionLabels,
              ),
              if (leads.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text('No leads yet. Open Admin → Load demo data to populate these reports.',
                      textAlign: TextAlign.center, style: context.texts.bodyMedium),
                ),
            ],
          );
        },
      ),
    );
  }

  Map<String, (int, int)> _group(
    List<Map<String, dynamic>> leads,
    List<String> Function(Map<String, dynamic>) keys,
  ) {
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

class _Chart extends StatelessWidget {
  const _Chart({required this.title, required this.data, this.labels = const {}, this.subtitle});
  final String title;
  final String? subtitle;
  final Map<String, (int, int)> data;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    final rows = data.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    final max = rows.isEmpty ? 1 : rows.first.value.$1;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      decoration: BoxDecoration(
        color: context.scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.r20),
        border: Border.all(color: context.scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.texts.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle!, style: context.texts.bodySmall?.copyWith(fontSize: 12.5)),
          ],
          const SizedBox(height: 10),
          Row(children: [
            _Legend(color: AppTheme.indigo.withValues(alpha: 0.25), label: 'leads'),
            const SizedBox(width: 14),
            const _Legend(color: AppTheme.human, label: 'admitted'),
          ]),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text('No data yet', style: context.texts.bodyMedium),
            ),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: LayoutBuilder(builder: (context, c) {
                final narrow = c.maxWidth < 520;
                final label = SizedBox(
                  width: narrow ? c.maxWidth : 150,
                  child: Text(labels[r.key] ?? r.key,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                );
                final pct = r.value.$1 == 0 ? 0 : (r.value.$2 * 100 / r.value.$1).round();
                final bar = _Bar(total: r.value.$1, admitted: r.value.$2, max: max);
                final value = SizedBox(
                  width: 104,
                  child: Text(
                    '${r.value.$1} · ${r.value.$2} adm ($pct%)',
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 11.5, color: context.scheme.onSurfaceVariant),
                  ),
                );
                if (narrow) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: label),
                      value,
                    ]),
                    const SizedBox(height: 6),
                    bar,
                  ]);
                }
                return Row(children: [label, Expanded(child: bar), const SizedBox(width: 10), value]);
              }),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.total, required this.admitted, required this.max});
  final int total;
  final int admitted;
  final int max;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth * total / (max == 0 ? 1 : max);
      final wa = total == 0 ? 0.0 : w * admitted / total;
      return SizedBox(
        height: 20,
        child: Stack(children: [
          Container(
            height: 20,
            width: w,
            decoration: BoxDecoration(
              color: AppTheme.indigo.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(7),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            height: 20,
            width: wa,
            decoration: BoxDecoration(
              color: AppTheme.human,
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ]),
      );
    });
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label, style: context.texts.bodySmall?.copyWith(fontSize: 11.5)),
      ]);
}


/// How the system behaves under load: AI calls actually made vs. answered from the cache,
/// batched, or absorbed as duplicates. Counters are sharded (see functions/src/stats.ts).
class _ScaleCard extends StatelessWidget {
  const _ScaleCard();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, num>>(
      stream: Repo.watchStats(),
      builder: (context, snap) {
        final s = snap.data ?? const <String, num>{};
        num v(String k) => s[k] ?? 0;
        final cached = v('cacheHits') + v('cacheWaits');
        final without = v('aiCalls') + cached + v('batched');
        final saved = without == 0 ? 0 : (100 * (1 - v('aiCalls') / without)).round();
        final tiles = [
          ('Replies sent', v('replies'), Icons.forum_rounded, AppTheme.indigo),
          ('AI calls made', v('aiCalls'), Icons.smart_toy_rounded, AppTheme.ai),
          ('Answered from cache', cached, Icons.bolt_rounded, AppTheme.coral),
          ('Messages batched', v('batched'), Icons.merge_type_rounded, AppTheme.info),
          ('Duplicate triggers absorbed', v('coalesced'), Icons.filter_alt_rounded, AppTheme.cold),
          ('Same person merged', v('merges'), Icons.call_merge_rounded, AppTheme.human),
          ('Family leads linked', v('linked'), Icons.family_restroom_rounded, AppTheme.info),
          ('Guard blocks', v('guardBlocks'), Icons.shield_rounded, AppTheme.guard),
          ('AI busy → retried', v('aiFailures'), Icons.replay_rounded, AppTheme.warm),
        ];
        return Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.scheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.r16),
            border: Border.all(color: context.scheme.outlineVariant),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Scale & cost', style: context.texts.titleMedium)),
              if (StaffScope.isAdmin(context))
                TextButton(onPressed: () => Repo.resetStats(), child: const Text('Reset counters')),
            ]),
            Text(
              without == 0
                  ? 'Run Admin → Demo → Load test to see how a burst of enquiries is handled.'
                  : 'Without caching and batching: ${without.round()} AI calls. Actually made: ${v('aiCalls').round()} ($saved% saved).',
              style: context.texts.bodySmall?.copyWith(fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final t in tiles)
                Container(
                  width: 168,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.$4.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(AppTheme.r12),
                    border: Border.all(color: t.$4.withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    Icon(t.$3, size: 18, color: t.$4),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${t.$2.round()}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        Text(t.$1, style: context.texts.bodySmall?.copyWith(fontSize: 11.5), maxLines: 2),
                      ]),
                    ),
                  ]),
                ),
            ]),
          ]),
        );
      },
    );
  }
}
