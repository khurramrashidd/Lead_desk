import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/team_service.dart';
import '../utils/ist.dart';

/// Admin: people who asked to become counsellors, and the current team.
class TeamSection extends StatelessWidget {
  const TeamSection({super.key});

  Future<void> _do(BuildContext context, Future<void> Function() job, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await job();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final myUid = AuthService.user?.uid;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: TeamService.watchPending(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? [];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Counsellor requests (${docs.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (docs.isEmpty)
              Text('No pending requests. New staff sign in on the desk and appear here.',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            for (final d in docs)
              Card(
                color: scheme.secondaryContainer.withValues(alpha: 0.5),
                child: ListTile(
                  leading: _avatar(d.data()),
                  title: Text(d.data()['name'] as String? ?? 'Unknown'),
                  subtitle: Text([
                    d.data()['email'] ?? '',
                    _methods(d.data()),
                    if (Ist.fromTimestamp(d.data()['requestedAt']) != null)
                      'asked ${Ist.relative(Ist.fromTimestamp(d.data()['requestedAt']))}',
                  ].where((e) => '$e'.isNotEmpty).join(' · ')),
                  trailing: Wrap(spacing: 4, children: [
                    IconButton(
                      tooltip: 'Reject',
                      icon: Icon(Icons.close, color: scheme.error),
                      onPressed: () => _do(context, () => TeamService.reject(d.id), 'Request rejected'),
                    ),
                    FilledButton(
                      onPressed: () => _do(context, () => TeamService.approve(d.id), '✅ Approved as counsellor'),
                      child: const Text('Approve'),
                    ),
                  ]),
                ),
              ),
          ]);
        },
      ),
      const SizedBox(height: 16),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: TeamService.watchTeam(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? [];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Team (${docs.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final d in docs)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _avatar(d.data()),
                title: Text('${d.data()['name'] ?? ''}${d.id == myUid ? ' (you)' : ''}'),
                subtitle: Text('${d.data()['email'] ?? ''} · ${_methods(d.data())}'),
                trailing: d.id == myUid
                    ? Chip(label: Text(d.data()['role'] as String? ?? ''))
                    : PopupMenuButton<String>(
                        tooltip: 'Change role',
                        onSelected: (r) => _do(context, () => TeamService.setRole(d.id, r), 'Role changed to $r'),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: Roles.counsellor, child: Text('Make counsellor')),
                          PopupMenuItem(value: Roles.admin, child: Text('Make admin')),
                          PopupMenuItem(value: Roles.rejected, child: Text('Remove access')),
                        ],
                        child: Chip(label: Text(d.data()['role'] as String? ?? '')),
                      ),
              ),
          ]);
        },
      ),
    ]);
  }

  static Widget _avatar(Map<String, dynamic> u) {
    final photo = u['photoUrl'] as String?;
    final name = (u['name'] as String?)?.trim() ?? '';
    return CircleAvatar(
      backgroundImage: photo != null ? NetworkImage(photo) : null,
      child: photo == null ? Text(name.isEmpty ? '?' : name[0].toUpperCase()) : null,
    );
  }

  static String _methods(Map<String, dynamic> u) {
    final p = (u['providers'] as List?)?.cast<String>() ?? const <String>[];
    final names = [
      if (p.contains('google.com')) 'Google',
      if (p.contains('password')) 'Email',
    ];
    return names.isEmpty ? '' : names.join(' + ');
  }
}
