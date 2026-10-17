import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/repo.dart';
import '../../utils/ist.dart';
import '../../widgets/lead_widgets.dart';

enum LeadFilter { all, mine, hot, needsHuman, followUpDue, demoBooked }

/// The live queue of enquiries. Newest activity first, merged duplicates hidden.
class LeadList extends StatefulWidget {
  const LeadList({super.key, required this.selectedId, required this.onSelect});
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  State<LeadList> createState() => _LeadListState();
}

class _LeadListState extends State<LeadList> {
  final _stream = Repo.watchLeads();
  final _search = TextEditingController();
  LeadFilter _filter = LeadFilter.all;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Map<String, dynamic> d) {
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty && !leadMatchesSearch(d, q)) return false;
    switch (_filter) {
      case LeadFilter.all:
        return true;
      case LeadFilter.mine:
        return d['assignedUid'] != null && d['assignedUid'] == AuthService.user?.uid;
      case LeadFilter.hot:
        return d['temperature'] == 'hot';
      case LeadFilter.needsHuman:
        return d['needsHuman'] == true || d['possibleDuplicateOf'] != null;
      case LeadFilter.followUpDue:
        final na = d['nextAction'] as Map?;
        final at = Ist.fromTimestamp(na?['at']);
        return na != null &&
            na['done'] != true &&
            at != null &&
            at.isBefore(DateTime.now().add(const Duration(hours: 24)));
      case LeadFilter.demoBooked:
        return d['status'] == 'demo_booked' || d['booking'] != null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.scheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                hintText: 'Search name, phone, email, question…',
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (final f in LeadFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: _FilterChip(
                      label: _label(f),
                      selected: _filter == f,
                      onTap: () => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) return _Message(icon: Icons.error_outline, text: 'Could not load leads.\n${snap.error}');
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.where((d) => _matches(d.data())).toList();
                if (docs.isEmpty) {
                  return _Message(
                    icon: Icons.inbox_outlined,
                    text: _query.isNotEmpty || _filter != LeadFilter.all
                        ? 'No leads match this filter.'
                        : 'No enquiries yet.\nOpen Admin → Load demo data, or chat as a student.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: docs.length,
                  separatorBuilder: (context, index) =>
                      Divider(height: 1, indent: 76, color: context.scheme.outlineVariant),
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
      ),
    );
  }

  String _label(LeadFilter f) => switch (f) {
        LeadFilter.all => 'All',
        LeadFilter.mine => '👤 Mine',
        LeadFilter.hot => '🔥 Hot',
        LeadFilter.needsHuman => '🙋 Needs you',
        LeadFilter.followUpDue => '⏰ Due',
        LeadFilter.demoBooked => '📅 Demo',
      };
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? AppTheme.indigo : context.scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : context.scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
}

class _LeadTile extends StatelessWidget {
  const _LeadTile({required this.id, required this.d, required this.selected, required this.onTap});
  final String id;
  final Map<String, dynamic> d;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final name = (d['name'] as String?)?.trim().isNotEmpty == true ? d['name'] as String : 'New enquiry';
    final latin = d['nameLatin'] as String?;
    final sources = (d['sources'] as List?)?.cast<String>() ?? const <String>[];
    final objections = (d['objections'] as List?)?.cast<String>() ?? const <String>[];
    final summary = (d['summary'] as List?)?.cast<String>() ?? const <String>[];
    final aliases = (d['aliases'] as List?)?.cast<String>() ?? const <String>[];
    final needsHuman = d['needsHuman'] == true;
    final temp = d['temperature'] as String?;

    return Material(
      color: selected ? AppTheme.indigo.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            if (selected)
              Positioned(
                left: 0,
                top: 8,
                bottom: 8,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: AppTheme.indigo,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ScoreBadge(score: (d['score'] as num?)?.toInt() ?? 0, temperature: temp),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                latin != null && latin.isNotEmpty && latin != name ? '$name · $latin' : name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, letterSpacing: -0.2),
                              ),
                            ),
                            if (needsHuman) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.pan_tool_rounded, size: 13, color: AppTheme.warm),
                            ],
                            if (d['aiPaused'] == true) ...[
                              const SizedBox(width: 5),
                              const Icon(Icons.headset_mic_rounded, size: 13, color: AppTheme.human),
                            ],
                            const Spacer(),
                            Text(
                              Ist.relative(Ist.fromTimestamp(d['lastMessageAt'])),
                              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          summary.isNotEmpty
                              ? summary.first
                              : sources.map((s) => sourceLabels[s] ?? s).join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.4),
                        ),
                        const SizedBox(height: 7),
                        Wrap(spacing: 5, runSpacing: 5, children: [
                          TempChip(temp),
                          for (final s in sources.take(2)) SmallChip(sourceLabels[s] ?? s),
                          if (aliases.isNotEmpty || d['mergedFromIds'] != null) const SmallChip('🔗 merged', color: AppTheme.ai),
                          if ((d['relatedLeads'] as Map?)?.isNotEmpty == true) const SmallChip('👪 linked', color: AppTheme.info),
                          if ((d['onboarding'] as Map?)?['step'] != null && (d['onboarding'] as Map?)?['step'] != 'done')
                            const SmallChip('📝 intake', color: AppTheme.info),
                          if (d['deliveryIssue'] != null) const SmallChip('⚠️ not delivered', color: AppTheme.hot),
                          if ((d['ai'] as Map?)?['lastError'] != null) const SmallChip('☁️ AI retrying', color: AppTheme.warm),
                          if (d['selftest'] == true)
                            const SmallChip('self-test')
                          else if (d['burst'] == true)
                            const SmallChip('load test')
                          else if (d['seed'] == true)
                            const SmallChip('sample'),
                          if ((d['assignedTo'] as String?)?.isNotEmpty == true) SmallChip('👤 ${d['assignedTo']}'),
                          for (final o in objections.take(2)) SmallChip(objectionLabels[o] ?? o, color: AppTheme.warm),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 38, color: context.scheme.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 14),
              Text(text,
                  textAlign: TextAlign.center,
                  style: context.texts.bodyMedium?.copyWith(fontSize: 13.5, height: 1.5)),
            ],
          ),
        ),
      );
}


/// Search over everything that identifies a person or their enquiry: names in any script,
/// every phone (any format: "+91 98765-43210" finds 9876543210), emails, Telegram username,
/// the questions they asked and the AI summary.
bool leadMatchesSearch(Map<String, dynamic> d, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  List<String> list(String k) => ((d[k] as List?) ?? const []).map((e) => e is Map ? '${e['text'] ?? e['name'] ?? ''} ${e['phone'] ?? ''} ${e['email'] ?? ''}' : '$e').toList();
  final fields = [
    d['name'], d['nameLatin'], d['phone'], d['email'], d['city'], d['assignedTo'], d['studentName'], d['studentPhone'],
    d['studentEmail'], d['telegramUsername'], d['firstSource'], d['waId'],
    ...list('aliases'),
    ...list('summary'),
    ...list('contactPhones'),
    ...list('contacts'),
    ...list('recentQuestions'),
  ].whereType<String>().map((f) => f.toLowerCase()).toList();
  if (fields.any((f) => f.contains(q))) return true;
  // A phone number typed in any format.
  final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length >= 4 && digits.length == q.replaceAll(RegExp(r'[\s+()-]'), '').length) {
    final tail = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
    return fields.any((f) => f.replaceAll(RegExp(r'[\s+()-]'), '').contains(tail));
  }
  return false;
}
