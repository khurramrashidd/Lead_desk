import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'data/links.dart';
import 'firebase_options.dart';
import 'l10n.dart';
import 'screens/master/master_dashboard.dart';
import 'screens/admin_screen.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/chat/prospect_chat_screen.dart';
import 'screens/demo_hub_screen.dart';
import 'screens/selftest_screen.dart';
import 'screens/form_screen.dart';
import 'screens/site/site_screen.dart';
import 'screens/walkin_screen.dart';
import 'screens/desk/desk_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Wait until a saved session (for example a signed-in counsellor on the web) is
  // restored, otherwise we would replace it with a new anonymous one on every refresh.
  final restored = await FirebaseAuth.instance.authStateChanges().first;
  if (restored == null) {
    await FirebaseAuth.instance.signInAnonymously(); // students chat without an account
  }
  await L10n.load();
  PublicLinks.watch(); // WhatsApp / Telegram / Google Form links behind the buttons and QR codes
  runApp(const LeadDeskApp());
}

class LeadDeskApp extends StatelessWidget {
  const LeadDeskApp({super.key});

  static final themeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'SechTummit Trainers · AI admissions counsellor',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        scrollBehavior: const _AppScrollBehavior(),
        // No initialRoute: on the web the browser URL decides the first page,
        // e.g. https://…/#/chat?src=instagram
        onGenerateRoute: (settings) {
          final uri = Uri.parse(settings.name ?? '/');
          final src = uri.queryParameters['src'];
          final Widget page;
          switch (uri.path) {
            case '/chat':
              page = ProspectChatScreen(source: src ?? 'web');
            case '/form':
              page = FormScreen(source: src ?? 'form');
            // Staff pages: Google/email sign-in + admin approval.
            case '/desk':
              page = const AuthGate(child: DeskScreen());
            case '/walkin':
              page = const AuthGate(child: WalkInScreen());
            case '/admin':
              page = const AuthGate(requireAdmin: true, child: AdminScreen());
            case '/demo':
              page = const DemoHubScreen();
            case '/master':
              page = const AuthGate(requireAdmin: true, child: MasterDashboard());
            case '/selftest':
              page = const AuthGate(requireAdmin: true, child: SelfTestScreen());
            default:
              page = SiteScreen(source: src ?? 'web', openChat: uri.queryParameters['chat'] == '1');
          }
          return MaterialPageRoute(builder: (_) => page, settings: settings);
        },
      ),
    );
  }
}

/// Lets the long marketing page be dragged with a mouse on the web, not just scrolled.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
