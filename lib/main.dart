import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'app_theme.dart';
import 'screens/admin_screen.dart';
import 'screens/chat/prospect_chat_screen.dart';
import 'screens/desk/desk_screen.dart';
import 'screens/form_screen.dart';
import 'screens/home_screen.dart';
import 'screens/walkin_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }
  runApp(const LeadDeskApp());
}

class LeadDeskApp extends StatefulWidget {
  const LeadDeskApp({super.key});

  static final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

  @override
  State<LeadDeskApp> createState() => _LeadDeskAppState();
}

class _LeadDeskAppState extends State<LeadDeskApp> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: LeadDeskApp.themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'AI Lead Desk',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        // No initialRoute: on web the browser URL (e.g. #/chat?src=instagram) decides the first page.
        onGenerateRoute: (settings) {
          // Works for web links like  https://your-app.web.app/#/chat?src=instagram
          final uri = Uri.parse(settings.name ?? '/');
          final src = uri.queryParameters['src'];
          Widget page;
          switch (uri.path) {
            case '/chat':
              page = ProspectChatScreen(source: src ?? 'web');
              break;
            case '/form':
              page = FormScreen(source: src ?? 'form');
              break;
            case '/desk':
              page = const DeskScreen();
              break;
            case '/walkin':
              page = const WalkInScreen();
              break;
            case '/admin':
              page = const AdminScreen();
              break;
            default:
              page = const HomeScreen();
          }
          return MaterialPageRoute(builder: (_) => page, settings: settings);
        },
      ),
    );
  }
}
