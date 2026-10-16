import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../services/auth_service.dart';
import 'auth_gate.dart';

/// Profile + linked sign-in methods. Lets one person use Google AND a password on the same account.
Future<void> showAccountSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _AccountSheet(),
  );
}

class _AccountSheet extends StatefulWidget {
  const _AccountSheet();

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  bool _busy = false;
  String? _message;

  Future<void> _run(Future<void> Function() job, String success) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await job();
      if (mounted) setState(() => _message = success);
    } catch (e) {
      if (mounted) setState(() => _message = AuthService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPassword() async {
    final c = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a password'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Then you can also sign in with ${AuthService.user?.email} + this password. Same account, same data.'),
          const SizedBox(height: 12),
          TextField(controller: c, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'New password (6+ characters)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Add')),
        ],
      ),
    );
    c.dispose();
    if (pw == null || pw.isEmpty) return;
    await _run(() => AuthService.linkPassword(pw), '✅ Password added. Google and email now open the same account.');
  }

  @override
  Widget build(BuildContext context) {
    final u = AuthService.user;
    final scheme = Theme.of(context).colorScheme;
    if (u == null) return const SizedBox(height: 120, child: Center(child: Text('Not signed in')));
    final photo = u.photoURL;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(
              radius: 26,
              backgroundImage: photo != null ? NetworkImage(photo) : null,
              child: photo == null ? Text(AuthService.displayName[0].toUpperCase()) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(AuthService.displayName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                Text(u.email ?? '', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                if (StaffScope.roleOf(context) != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.indigo.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      StaffScope.roleOf(context)!.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppTheme.indigo),
                    ),
                  ),
                ],
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          if (!u.emailVerified && AuthService.hasPassword)
            Card(
              color: scheme.tertiaryContainer,
              child: ListTile(
                leading: const Icon(Icons.mark_email_unread_outlined),
                title: const Text('Please verify your email'),
                subtitle: const Text('Verified emails keep their password when the same Gmail also uses Google.'),
                trailing: TextButton(
                  onPressed: _busy ? null : () => _run(AuthService.resendVerification, 'Verification link sent.'),
                  child: const Text('Resend'),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text('Sign-in methods on this account', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(radius: 16, child: Text('G', style: TextStyle(fontWeight: FontWeight.w800))),
            title: const Text('Google'),
            trailing: AuthService.hasGoogle
                ? const Chip(label: Text('Linked ✓'))
                : OutlinedButton(
                    onPressed: _busy ? null : () => _run(AuthService.linkGoogle, '✅ Google linked to this account.'),
                    child: const Text('Link Google'),
                  ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(radius: 16, child: Icon(Icons.lock_outline, size: 18)),
            title: const Text('Email + password'),
            trailing: AuthService.hasPassword
                ? const Chip(label: Text('Linked ✓'))
                : OutlinedButton(onPressed: _busy ? null : _addPassword, child: const Text('Add password')),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_message != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, textAlign: TextAlign.center)),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            onPressed: () async {
              final nav = Navigator.of(context);
              await AuthService.signOut();
              nav.pop();
            },
          ),
        ]),
      ),
    );
  }
}
