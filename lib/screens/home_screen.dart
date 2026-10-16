import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../utils/ist.dart';
import '../utils/responsive.dart';
import 'auth/account_sheet.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = [
      _Entry(Icons.dashboard_customize, 'Counsellor Desk', 'Live leads, scores, objections, take over chats', '/desk'),
      _Entry(Icons.chat_bubble, 'Student Chat', 'What a prospect sees (text + voice notes)', '/chat'),
      _Entry(Icons.assignment, 'Website Form', 'Enquiry form that continues into chat', '/form'),
      _Entry(Icons.storefront, 'Walk-in Entry', 'Add a visitor with auto location', '/walkin'),
      _Entry(Icons.admin_panel_settings, 'Admin & Demo', 'Courses, demo data, QR codes, time machine', '/admin'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Lead Desk'),
        actions: [
          Center(child: IstClock(compact: MediaQuery.sizeOf(context).width < 600)),
          // Staff account: avatar when signed in, otherwise a sign-in shortcut.
          StreamBuilder<User?>(
            stream: FirebaseAuth.instance.userChanges(),
            builder: (context, snap) {
              final u = snap.data;
              if (u == null || u.isAnonymous) {
                if (MediaQuery.sizeOf(context).width < 600) {
                  return IconButton(
                    tooltip: 'Staff sign in',
                    icon: const Icon(Icons.login),
                    onPressed: () => Navigator.pushNamed(context, '/desk'),
                  );
                }
                return TextButton.icon(
                  icon: const Icon(Icons.login, size: 18),
                  label: const Text('Staff sign in'),
                  onPressed: () => Navigator.pushNamed(context, '/desk'),
                );
              }
              return IconButton(
                tooltip: AuthService.displayName,
                onPressed: () => showAccountSheet(context),
                icon: CircleAvatar(
                  radius: 15,
                  backgroundImage: u.photoURL != null ? NetworkImage(u.photoURL!) : null,
                  child: u.photoURL == null ? Text(AuthService.displayName[0].toUpperCase()) : null,
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Light / dark',
            icon: const Icon(Icons.brightness_6),
            onPressed: () {
              final m = LeadDeskApp.themeMode;
              m.value = Theme.of(context).brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
        ],
      ),
      body: MaxWidth(
        width: 900,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Every enquiry answered in seconds. No lead forgotten.',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('English · हिंदी · मराठी — text and voice notes', style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth > 640 ? 2 : 1;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final e in items)
                    SizedBox(
                      width: (c.maxWidth - 12 * (cols - 1)) / cols,
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          leading: CircleAvatar(
                            backgroundColor: scheme.primaryContainer,
                            child: Icon(e.icon, color: scheme.onPrimaryContainer),
                          ),
                          title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(e.subtitle),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pushNamed(context, e.route),
                        ),
                      ),
                    ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _Entry {
  _Entry(this.icon, this.title, this.subtitle, this.route);
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
}
