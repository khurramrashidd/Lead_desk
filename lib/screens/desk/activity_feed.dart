import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../services/repo.dart';
import '../../utils/ist.dart';

/// Live feed of what the system did by itself: merges, blocked claims, bookings, reminders.
class ActivityFeed extends StatelessWidget {
  const ActivityFeed({super.key, this.onOpenLead});
  final ValueChanged<String>? onOpenLead;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: Repo.watchEvents(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Text('⚡ Live activity', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: docs.isEmpty
                ? Center(child: Text('Nothing yet', style: TextStyle(color: scheme.onSurfaceVariant)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final e = docs[i].data();
                      final (icon, color, title, body) = _describe(e);
                      final leadId = e['leadId'] as String?;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: color.withValues(alpha: 0.15),
                            child: Text(icon),
                          ),
                          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('$body\n${Ist.relative(Ist.fromTimestamp(e['at']))}'),
                          isThreeLine: true,
                          onTap: leadId == null || onOpenLead == null ? null : () => onOpenLead!(leadId),
                        ),
                      );
                    },
                  ),
          ),
        ]);
      },
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
          '"${merged['name']}" (${merged['source']}, ${merged['phone']}) merged into "${kept['name']}" (${kept['source']}). ${data['reason']} · match ${data['similarity']}',
        );
      case 'guard_block':
        final v = (data['violations'] as List?)?.join('; ') ?? '';
        return ('🛡', AppTheme.guard, 'Guard blocked an invented claim', v);
      case 'booking':
        return ('📅', AppTheme.human, 'Demo class booked', '${data['title'] ?? ''}');
      case 'reminder':
        return ('⏰', AppTheme.warm, 'Reminder sent (${data['kind']})', '${data['title'] ?? ''}');
      case 'followup':
        return ('📨', AppTheme.seed, 'Follow-up sent automatically', '${data['reason'] ?? ''}');
      case 'possible_duplicate':
        return ('⚠️', AppTheme.warm, 'Possible duplicate', '${data['reason'] ?? ''}');
      default:
        return ('•', AppTheme.cold, '${e['type']}', '');
    }
  }
}
