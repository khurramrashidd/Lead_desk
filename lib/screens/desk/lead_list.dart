import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../services/repo.dart';
import '../../utils/ist.dart';
import '../../widgets/lead_widgets.dart';

enum LeadFilter { all, hot, needsHuman, followUpDue, demoBooked }

class LeadList extends StatefulWidget {
  const LeadList({super.key, required this.selectedId, required this.onSelect});
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  State<LeadList> createState() => _LeadListState();
}

class _LeadListState extends State<LeadList> {
  LeadFilter _filter = LeadFilter.all;
  String _query = '';
  final _stream = Repo.watchLeads(); // one live subscription, reused on every rebuild

  bool _matches(Map<String, dynamic> d) {
    final q = _query.toLowerCase();
    if (q.isNotEmpty) {
      final hay = '${d['name'] ?? ''} ${d['nameLatin'] ?? ''} ${d['phone'] ?? ''} ${d['city'] ?? ''}'.toLowerCase();
      if (!hay.contains(q)) return false;
    }
    switch (_filter) {
      case LeadFilter.all:
        return true;
      case LeadFilter.hot:
        return d['temperature'] == 'hot';
      case LeadFilter.needsHuman:
        return d['needsHuman'] == true || d['possibleDuplicateOf'] != null;
      case LeadFilter.followUpDue:
        final na = d['nextAction'] as Map?;
        final at = Ist.fromTimestamp(na?['at']);
        return na != null && na['done'] != true && at != null && at.isBefore(DateTime.now().add(const Duration(hours: 24)));
      case LeadFilter.demoBooked:
        return d['status'] == 'demo_booked';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name, phone, city'),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final f in LeadFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(_label(f)),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
            stream: _stream,
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.where((d) => _matches(d.data())).toList();
              if (docs.isEmpty) {
                return Center(
                  child: Text('No leads here yet.\nOpen Admin → Load demo data, or chat as a student.',
                      textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                );
              }
              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (context, index) => const Divider(height: 1, indent: 72),
                itemBuilder: (context, i) => _LeadTile(
                  id: docs[i].id,
                  d: docs[i].data(),
                  selected: docs[i].id == widget.selectedId,
                  onTap: () => widget.onSelect(docs[i].id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _label(LeadFilter f) => switch (f) {
        LeadFilter.all => 'All',
        LeadFilter.hot => '🔥 Hot',
        LeadFilter.needsHuman => '🙋 Needs you',
        LeadFilter.followUpDue => '⏰ Follow-up due',
        LeadFilter.demoBooked => '📅 Demo booked',
      };
}

class _LeadTile extends StatelessWidget {
  const _LeadTile({required this.id, required this.d, required this.selected, required this.onTap});
  final String id;
  final Map<String, dynamic> d;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = (d['name'] as String?)?.isNotEmpty == true ? d['name'] as String : 'New enquiry';
    final latin = d['nameLatin'] as String?;
    final sources = (d['sources'] as List?)?.cast<String>() ?? const <String>[];
    final objections = (d['objections'] as List?)?.cast<String>() ?? const <String>[];
    final summary = (d['summary'] as List?)?.cast<String>() ?? const <String>[];
    final needsHuman = d['needsHuman'] == true;
    final aliases = (d['aliases'] as List?)?.cast<String>() ?? const <String>[];

    return Material(
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.45) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ScoreBadge(score: (d['score'] as num?)?.toInt() ?? 0, temperature: d['temperature'] as String?),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(
                      latin != null && latin != name ? '$name · $latin' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (needsHuman) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.priority_high, size: 16, color: AppTheme.hot),
                  ],
                  if (d['aiPaused'] == true) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.headset_mic, size: 16, color: AppTheme.human),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(
                  summary.isNotEmpty ? summary.first : (sources.map((s) => sourceLabels[s] ?? s).join(' · ')),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  TempChip(d['temperature'] as String?),
                  for (final s in sources.take(3)) SmallChip(sourceLabels[s] ?? s),
                  if (aliases.isNotEmpty) const SmallChip('🔗 merged', color: AppTheme.ai),
                  for (final o in objections.take(2)) SmallChip(objectionLabels[o] ?? o, color: AppTheme.warm),
                ]),
              ]),
            ),
            const SizedBox(width: 8),
            Text(Ist.relative(Ist.fromTimestamp(d['lastMessageAt'])),
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}
