import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../services/repo.dart';
import '../../utils/ist.dart';

/// What the system did on its own: merged a person, blocked an invented claim,
/// booked a demo, sent a reminder, fired a follow-up. This is the proof panel.
class ActivityFeed extends StatelessWidget {
  const ActivityFeed({super.key, this.onOpenLead});
  final ValueChanged<String>? onOpenLead;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.scheme.surface,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Repo.watchEvents(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                child: Row(children: [
                  const Icon(Icons.bolt_rounded, size: 18, color: AppTheme.indigo),
                  const SizedBox(width: 8),
                  Text('Live activity', style: context.texts.titleMedium),
                  const Spacer(),
                  Text('${docs.length}', style: context.texts.bodySmall),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: docs.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text(
                            'Nothing yet.\nChat as a student, or use the ⏩ time machine to fire follow-ups.',
                            textAlign: TextAlign.center,
                            style: context.texts.bodyMedium?.copyWith(fontSize: 13.5),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          final e = docs[i].data();
                          final leadId = e['leadId'] as String?;
                          final v = _describe(e);
                          return _EventTile(
                            icon: v.$1,
                            color: v.$2,
                            title: v.$3,
                            body: v.$4,
                            when: Ist.relative(Ist.fromTimestamp(e['at'])),
                            onTap: leadId == null || onOpenLead == null ? null : () => onOpenLead!(leadId),
                            first: i == 0,
                            last: i == docs.length - 1,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  (String, Color, String, String) _describe(Map<String, dynamic> e) {
    final data = (e['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    switch (e['type']) {
      case 'merge':
        final kept = (data['kept'] as Map?) ?? const {};
        final merged = (data['merged'] as Map?) ?? const {};
        return (
          '🔗',
          AppTheme.ai,
          'Same person recognised',
          '“${merged['name']}” (${merged['source']}) merged into “${kept['name']}” (${kept['source']}). '
              '${data['reason']} · match ${data['similarity']}',
        );
      case 'guard_block':
        return ('🛡', AppTheme.guard, 'Guard blocked an invented claim',
            (data['violations'] as List?)?.join('; ') ?? '');
      case 'booking':
        return ('📅', AppTheme.human, 'Demo class booked', '${data['title'] ?? ''}');
      case 'reminder':
        return ('⏰', AppTheme.warm, 'Reminder sent (${data['kind']})', '${data['title'] ?? ''}');
      case 'followup':
        return ('📨', AppTheme.info, 'Follow-up sent automatically',
            '${data['reason'] ?? ''}\n“${data['message'] ?? ''}”');
      case 'possible_duplicate':
        return ('⚠️', AppTheme.warm, 'Possible duplicate flagged', '${data['reason'] ?? ''}');
      case 'staff_admin':
        return ('👑', AppTheme.indigo, 'Admin unlocked', '${data['email'] ?? ''} — ${data['reason'] ?? ''}');
      case 'staff_request':
        return ('🙋', AppTheme.cold, 'Counsellor access requested', '${data['email'] ?? ''}');
      default:
        return ('•', AppTheme.cold, '${e['type']}', '');
    }
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.when,
    required this.first,
    required this.last,
    this.onTap,
  });

  final String icon;
  final Color color;
  final String title;
  final String body;
  final String when;
  final bool first;
  final bool last;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // timeline rail
          SizedBox(
            width: 34,
            child: Column(children: [
              Container(width: 2, height: 8, color: first ? Colors.transparent : context.scheme.outlineVariant),
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(icon, style: const TextStyle(fontSize: 13)),
              ),
              Expanded(
                child: Container(width: 2, color: last ? Colors.transparent : context.scheme.outlineVariant),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Material(
                color: context.scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppTheme.r12),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(AppTheme.r12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(title,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.2)),
                          ),
                          Text(when, style: context.texts.bodySmall?.copyWith(fontSize: 10.5)),
                        ]),
                        if (body.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(body,
                              style: context.texts.bodySmall?.copyWith(fontSize: 12.2, height: 1.45)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
