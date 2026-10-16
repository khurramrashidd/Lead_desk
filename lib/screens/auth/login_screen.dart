import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../services/auth_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/brand.dart';

/// Staff sign-in. Google or email + password — the same Gmail opens one account
/// either way. Students never see this screen; their chat needs no account.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _createMode = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------- Google
  Future<void> _google() => _guard(() async {
        try {
          await AuthService.signInWithGoogle();
        } on FirebaseAuthException catch (e) {
          if (e.code == 'account-exists-with-different-credential' && e.credential != null && e.email != null) {
            await _askPasswordThenLink(e.email!, e.credential!);
          } else {
            rethrow;
          }
        }
      });

  Future<void> _askPasswordThenLink(String email, AuthCredential pending) async {
    if (!mounted) return;
    final pw = await _askPassword(
      title: 'Link Google to your account',
      message: '$email already has an account with a password. Enter it once and Google will open '
          'the same account from now on.',
    );
    if (pw == null) return;
    await AuthService.signInWithPasswordAndLink(email, pw, pending);
    _snack('Google is now linked to your account.');
  }

  // ----------------------------------------------------------------- email
  Future<void> _submitEmail() async {
    if (!_form.currentState!.validate()) return;
    await _guard(() async {
      if (!_createMode) {
        await AuthService.signInWithEmail(_email.text, _password.text);
        return;
      }
      try {
        await AuthService.signUpWithEmail(name: _name.text, email: _email.text, password: _password.text);
        _snack('Account created. We sent a verification link to ${_email.text.trim()}.');
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          await _offerMergeWithGoogle();
        } else {
          rethrow;
        }
      }
    });
  }

  /// "Create account" with an email that already signed in with Google:
  /// continue with Google once, then attach this password to the SAME account.
  Future<void> _offerMergeWithGoogle() async {
    final typedEmail = _email.text.trim().toLowerCase();
    final typedPassword = _password.text;
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.merge_type_rounded, size: 30),
        title: const Text('You already have an account'),
        content: Text(
          '$typedEmail is already registered. If you used Google before, continue with Google and we will add '
          'this password to the same account — then either way signs you in.\n\n'
          'Forgot your password instead? Tap Cancel and use "Forgot password".',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue with Google')),
        ],
      ),
    );
    if (go != true) return;
    await AuthService.signInWithGoogle();
    final googleEmail = (AuthService.user?.email ?? '').toLowerCase();
    if (googleEmail != typedEmail) {
      throw FirebaseAuthException(
        code: 'email-mismatch',
        message: 'You picked $googleEmail on Google, not $typedEmail. You are signed in with Google; no password was added.',
      );
    }
    if (!AuthService.hasPassword) {
      await AuthService.linkPassword(typedPassword);
      _snack('Merged — Google and your password now open the same account.');
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Type your email first, then tap "Forgot password".');
      return;
    }
    await _guard(() async {
      await AuthService.resetPassword(email);
      _snack('Password reset link sent to $email (if an account exists).');
    });
  }

  Future<String?> _askPassword({required String title, required String message}) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(message, style: const TextStyle(height: 1.5)),
          const SizedBox(height: 16),
          TextField(
            controller: c,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Continue')),
        ],
      ),
    );
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ------------------------------------------------------------------ view
  @override
  Widget build(BuildContext context) {
    final wide = screenSizeOf(context) == ScreenSize.desktop;
    return Scaffold(
      backgroundColor: context.scheme.surface,
      body: SafeArea(
        child: wide
            ? Row(children: [
                const Expanded(flex: 5, child: _Showcase()),
                Expanded(flex: 4, child: Center(child: SingleChildScrollView(child: _form_(context)))),
              ])
            : Center(child: SingleChildScrollView(child: _form_(context))),
      ),
    );
  }

  Widget _form_(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 32, 26, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(alignment: Alignment.centerLeft, child: const LeadDeskLogo(size: 32)),
            const SizedBox(height: 28),
            Text('Staff sign in', style: context.texts.headlineSmall),
            const SizedBox(height: 6),
            Text(
              'For counsellors and admins at SechTummit Trainers. '
              'Students do not need an account — they just chat.',
              style: context.texts.bodyMedium?.copyWith(fontSize: 13.5),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 3,
              child: _busy ? const LinearProgressIndicator(minHeight: 3) : const SizedBox.shrink(),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const _GoogleG(),
              label: const Text('Continue with Google'),
              onPressed: _busy ? null : _google,
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: Divider(color: context.scheme.outlineVariant)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or use email', style: context.texts.bodySmall?.copyWith(fontSize: 12)),
              ),
              Expanded(child: Divider(color: context.scheme.outlineVariant)),
            ]),
            const SizedBox(height: 20),
            SegmentedButton<bool>(
              style: SegmentedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              segments: const [
                ButtonSegment(value: false, label: Text('Sign in')),
                ButtonSegment(value: true, label: Text('Create account')),
              ],
              selected: {_createMode},
              onSelectionChanged: (s) => setState(() {
                _createMode = s.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 18),
            Form(
              key: _form,
              child: Column(children: [
                if (_createMode) ...[
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.badge_outlined)),
                    validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your name' : null,
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                  validator: (v) => (v ?? '').contains('@') ? null : 'Enter a valid email',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _hidePassword,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _submitEmail(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _hidePassword = !_hidePassword),
                    ),
                  ),
                  validator: (v) => (v ?? '').length < 6 ? 'At least 6 characters' : null,
                ),
              ]),
            ),
            if (!_createMode)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: _busy ? null : _forgot, child: const Text('Forgot password?')),
              )
            else
              const SizedBox(height: 10),
            const SizedBox(height: 6),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy ? null : _submitEmail,
              child: Text(_createMode ? 'Create account' : 'Sign in'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.scheme.errorContainer,
                  borderRadius: BorderRadius.circular(AppTheme.r12),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.error_outline, size: 18, color: context.scheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_error!,
                        style: TextStyle(color: context.scheme.onErrorContainer, fontSize: 13, height: 1.45)),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 22),
            Text(
              'New counsellors get access once an admin approves the request.',
              textAlign: TextAlign.center,
              style: context.texts.bodySmall?.copyWith(fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back to the website'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dark half of the sign-in page: what the desk is for.
class _Showcase extends StatelessWidget {
  const _Showcase();

  @override
  Widget build(BuildContext context) {
    const points = [
      ('⚡', 'Every enquiry answered in seconds', 'WhatsApp, Instagram, the website and walk-ins land in one queue.'),
      ('🧠', 'Scored, summarised, explained', 'Three lines, the objections raised, and the next message to send.'),
      ('🎧', 'Take over in one tap', 'Asha stops the moment you step in, and picks up again when you hand back.'),
    ];
    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const InstituteLogo(size: 36, onDark: true),
          const SizedBox(height: 48),
          Text('The counsellor desk\nthat never sleeps.',
              style: context.texts.displaySmall?.copyWith(color: Colors.white)),
          const SizedBox(height: 36),
          for (final p in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                  ),
                  child: Text(p.$1, style: const TextStyle(fontSize: 19)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.$2, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15.5)),
                    const SizedBox(height: 3),
                    Text(p.$3,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13.5, height: 1.5)),
                  ]),
                ),
              ]),
            ),
          const Spacer(),
          Row(children: [
            const LeadDeskLogo(size: 22, onDark: true),
            const SizedBox(width: 10),
            Text('· Kurukshetra 2026 prototype',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
          ]),
        ],
      ),
    );
  }
}

/// Google's four-colour G, drawn as four rounded blocks — no bundled asset.
class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GPainter()),
    );
  }
}

class _GPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final stroke = r * 0.42;
    final rect = Rect.fromCircle(center: c, radius: r - stroke / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;

    void arc(double startDeg, double sweepDeg, Color color) {
      p.color = color;
      canvas.drawArc(rect, startDeg * 3.1415926 / 180, sweepDeg * 3.1415926 / 180, false, p);
    }

    arc(-18, -72, const Color(0xFFEA4335)); // red, top right going up
    arc(-90, -80, const Color(0xFFFBBC05)); // yellow, left top
    arc(-170, -100, const Color(0xFF34A853)); // green, bottom left
    arc(90, -108, const Color(0xFF4285F4)); // blue, right side
    // the bar of the G
    canvas.drawRect(
      Rect.fromLTWH(c.dx, c.dy - stroke * 0.45, r - stroke * 0.2, stroke * 0.9),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
