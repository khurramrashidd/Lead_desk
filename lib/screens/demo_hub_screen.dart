import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/ist.dart';
import '../utils/responsive.dart';
import '../widgets/brand.dart';
import '../widgets/site_widgets.dart';

/// One page for judges and mentors: every entry point in the prototype,
/// plus the three-minute demo route.
class DemoHubScreen extends StatelessWidget {
  const DemoHubScreen({super.key});

  static const _entries = [
    (
      Icons.public,
      'Institute website',
      'What a prospective student lands on. The AI counsellor sits in the corner of it.',
      '/',
      AppTheme.navy,
    ),
    (
      Icons.chat_bubble_rounded,
      'Student chat',
      'Full-screen conversation — text and voice notes in English, हिंदी, मराठी.',
      '/chat',
      AppTheme.indigo,
    ),
    (
      Icons.edit_note_rounded,
      'Website enquiry form',
      'A form submission that continues straight into a counselling conversation.',
      '/form',
      AppTheme.info,
    ),
    (
      Icons.dashboard_rounded,
      'Counsellor desk',
      'Live leads with score, summary, objections, next best action and one-tap take over.',
      '/desk',
      AppTheme.ai,
    ),
    (
      Icons.storefront_rounded,
      'Walk-in entry',
      'Front-desk capture with automatic location and IST timestamp.',
      '/walkin',
      AppTheme.human,
    ),
    (
      Icons.admin_panel_settings_rounded,
      'Admin console',
      'Approve counsellors, edit the knowledge base, load demo data, print QR codes.',
      '/admin',
      AppTheme.amberDeep,
    ),
  ];

  static const _script = [
    ('1', 'Scan and speak', 'A judge scans the QR on screen and sends a Marathi voice note. Asha replies in Marathi in seconds.'),
    ('2', 'Watch the desk', 'The lead appears live with a score, a three-line summary and the objections detected.'),
    ('3', 'Try to break it', 'Demand a 50% discount or a job guarantee. The Guard blocks the invented claim and rewrites the reply.'),
    ('4', 'One person, one timeline', 'Submit the form as "Rahul Patil", then chat as "राहुल पाटील" — the two merge.'),
    ('5', 'Take over', 'Tap Take over on the phone. Asha stops instantly and your reply lands in the judge\'s chat.'),
    ('6', 'No lead forgotten', 'Hit ⏩ Fast-forward 1 day — reminders and follow-ups fire with their reasons.'),
  ];

  @override
  Widget build(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
    return Scaffold(
      backgroundColor: context.scheme.surfaceContainerLow,
      appBar: AppBar(
        title: const LeadDeskLogo(size: 26),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(child: IstClock(compact: phone)),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: phone ? 18 : 28, vertical: 24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Kurukshetra 2026 · PS3', icon: Icons.flag_rounded),
                  const SizedBox(height: 14),
                  Text('AI Lead Desk — demo hub',
                      style: (phone ? context.texts.headlineSmall : context.texts.headlineLarge)),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 740),
                    child: Text(
                      'An AI admissions counsellor that answers every enquiry in seconds — in English, Hindi and Marathi, '
                      'by text or voice note — plus a live counsellor desk so no lead is ever forgotten. '
                      'Built for SechTummit Trainers.',
                      style: context.texts.bodyLarge?.copyWith(fontSize: phone ? 15 : 16.5),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text('Open any part', style: context.texts.titleMedium),
                  const SizedBox(height: 14),
                  ResponsiveGrid(
                    minItemWidth: 300,
                    children: [
                      for (final e in _entries)
                        SurfaceCard(
                          onTap: () => Navigator.of(context).pushNamed(e.$4),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            IconBadge(icon: e.$1, color: e.$5, size: 44),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text(e.$2, style: context.texts.titleSmall?.copyWith(fontSize: 15))),
                                  const Icon(Icons.arrow_outward_rounded, size: 16),
                                ]),
                                const SizedBox(height: 5),
                                Text(e.$3, style: context.texts.bodyMedium?.copyWith(fontSize: 13.2)),
                              ]),
                            ),
                          ]),
                        ),
                    ],
                  ),
                  const SizedBox(height: 36),
                  Text('Three-minute demo route', style: context.texts.titleMedium),
                  const SizedBox(height: 14),
                  SurfaceCard(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
                    child: Column(
                      children: [
                        for (final s in _script)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                width: 28,
                                height: 28,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  gradient: AppTheme.brandGradient,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Text(s.$1,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(s.$2, style: context.texts.titleSmall?.copyWith(fontSize: 14.5)),
                                  const SizedBox(height: 3),
                                  Text(s.$3, style: context.texts.bodyMedium?.copyWith(fontSize: 13.2)),
                                ]),
                              ),
                            ]),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  SurfaceCard(
                    accent: AppTheme.warm,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const IconBadge(icon: Icons.info_outline_rounded, color: AppTheme.warm, size: 40),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Honest about the prototype', style: context.texts.titleSmall?.copyWith(fontSize: 14.5)),
                          const SizedBox(height: 5),
                          Text(
                            'SechTummit Trainers is a stand-in brand for the demo. Courses, fees, partner names and student '
                            'stories on the website are sample content, editable in Admin. Telephony and Instagram DMs — '
                            'the optional parts of the statement — are not built; Instagram leads are tracked with a tagged link.',
                            style: context.texts.bodyMedium?.copyWith(fontSize: 13.2),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
