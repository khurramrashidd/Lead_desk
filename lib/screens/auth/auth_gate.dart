import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../config.dart';
import '../../services/auth_service.dart';
import '../../services/team_service.dart';
import '../../utils/ist.dart';
import '../../utils/responsive.dart';
import '../../widgets/brand.dart';
import 'account_sheet.dart';
import 'login_screen.dart';

/// Gives the pages below it the signed-in staff member's role.
class StaffScope extends InheritedWidget {
  const StaffScope({super.key, required this.role, required super.child});
  final String role;

  static String? roleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StaffScope>()?.role;

  static bool isAdmin(BuildContext context) => roleOf(context) == Roles.admin;

  @override
  bool updateShouldNotify(StaffScope oldWidget) => oldWidget.role != role;
}

/// Staff pages: sign in (Google or email) → request access → an admin approves
/// → the desk opens. Students never need this; their chat has no account.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.child, this.requireAdmin = false});
  final Widget child;
  final bool requireAdmin;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snap) {
        final u = snap.data;
        if (u == null || u.isAnonymous) return const LoginScreen();
        return _RoleGate(key: ValueKey(u.uid), requireAdmin: requireAdmin, child: child);
      },
    );
  }
}

class _RoleGate extends StatefulWidget {
  const _RoleGate({super.key, required this.child, required this.requireAdmin});
  final Widget child;
  final bool requireAdmin;

  @override
  State<_RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<_RoleGate> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _record;

  @override
  void initState() {
    super.initState();
    // Creates the access request on first sign-in (role "pending").
    AuthService.saveProfile().catchError((Object e) => debugPrint('saveProfile failed: $e'));
    _record = AuthService.watchMyRecord();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _record,
      builder: (context, snap) {
        if (snap.hasError) {
          return _Gatehouse(
            icon: Icons.error_outline_rounded,
            title: 'Could not load your account',
            body: '${snap.error}',
          );
        }
        final data = snap.data?.data();
        if (data == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final role = data['role'] as String? ?? Roles.pending;

        if (role == Roles.rejected) {
          return const _Gatehouse(
            icon: Icons.block_rounded,
            title: 'Access not approved',
            body: 'An admin declined this request. Ask your admin if this looks like a mistake.',
          );
        }
        if (!Roles.canUseDesk(role)) {
          final at = Ist.fromTimestamp(data['requestedAt']);
          return _Gatehouse(
            icon: Icons.hourglass_top_rounded,
            title: 'Request sent to the admin',
            body: 'Hi ${AuthService.displayName}. Your request to join as a counsellor is waiting for approval'
                '${at == null ? '' : ' (sent ${Ist.full(at)})'}.\n\n'
                'This page opens the desk by itself the moment an admin approves you.',
            showOwnerUnlock: true,
          );
        }
        if (widget.requireAdmin && role != Roles.admin) {
          return const _Gatehouse(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Admins only',
            body: 'This page is for admins. Your counsellor desk is still open.',
          );
        }
        return StaffScope(role: role, child: widget.child);
      },
    );
  }
}

/// The waiting / blocked screen, with an owner escape hatch.
class _Gatehouse extends StatefulWidget {
  const _Gatehouse({
    required this.icon,
    required this.title,
    required this.body,
    this.showOwnerUnlock = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool showOwnerUnlock;

  @override
  State<_Gatehouse> createState() => _GatehouseState();
}

class _GatehouseState extends State<_Gatehouse> {
  bool _busy = false;
  String? _message;

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await TeamService.claimOwnerAdmin();
      // The role stream updates by itself and the desk opens.
    } catch (e) {
      setState(() => _message = 'Could not unlock: $e\n\n'
          'Check that your email is in kOwnerEmails (lib/config.dart) AND in ownerEmails() '
          'in firestore.rules, then run: deploy');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = widget.showOwnerUnlock && isOwnerEmail(AuthService.user?.email);
    return Scaffold(
      backgroundColor: context.scheme.surfaceContainerLow,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: MaxWidth(
              width: 520,
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(32, 36, 32, 28),
                  decoration: BoxDecoration(
                    color: context.scheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.r28),
                    border: Border.all(color: context.scheme.outlineVariant),
                    boxShadow: AppTheme.lift(context),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BrandMark(size: 52),
                      const SizedBox(height: 26),
                      Container(
                        width: 58,
                        height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.indigo.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(widget.icon, size: 28, color: AppTheme.indigo),
                      ),
                      const SizedBox(height: 18),
                      Text(widget.title, textAlign: TextAlign.center, style: context.texts.headlineSmall),
                      const SizedBox(height: 10),
                      Text(
                        widget.body,
                        textAlign: TextAlign.center,
                        style: context.texts.bodyMedium?.copyWith(fontSize: 14, height: 1.6),
                      ),
                      if (owner) ...[
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.amber.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(AppTheme.r16),
                            border: Border.all(color: AppTheme.amber.withValues(alpha: 0.3)),
                          ),
                          child: Column(children: [
                            Text(
                              'You are listed as the project owner. If the automatic promotion did not run, '
                              'unlock admin for yourself here.',
                              textAlign: TextAlign.center,
                              style: context.texts.bodySmall?.copyWith(fontSize: 12.8, height: 1.5),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.amberDeep,
                                minimumSize: const Size.fromHeight(46),
                              ),
                              icon: _busy
                                  ? const SizedBox(
                                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.vpn_key_rounded, size: 18),
                              label: const Text('Unlock admin access'),
                              onPressed: _busy ? null : _unlock,
                            ),
                          ]),
                        ),
                      ],
                      if (_message != null) ...[
                        const SizedBox(height: 14),
                        Text(_message!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: context.scheme.error, fontSize: 12.5, height: 1.5)),
                      ],
                      const SizedBox(height: 22),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        TextButton.icon(
                          icon: const Icon(Icons.manage_accounts_outlined, size: 17),
                          label: const Text('Account'),
                          onPressed: () => showAccountSheet(context),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          icon: const Icon(Icons.public, size: 17),
                          label: const Text('Website'),
                          onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
