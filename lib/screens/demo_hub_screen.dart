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
      Icons.fact_check_rounded,
      'PS3 self-test (proof)',
      'Runs every sentence of the problem statement live and shows pass/fail with the real conversation as evidence.',
      '/selftest',
      AppTheme.success,
    ),
    (
      Icons.admin_panel_settings_rounded,
      'Admin console',
      'AI keys and models, every channel, the knowledge base, demo data and QR codes.',
      '/admin',
      AppTheme.amberDeep,
    ),
  ];

  static const _script = [
    ('1', 'Ask the real question', 'Open the website chat (or scan the QR / message the Telegram bot) and send: "I\'m a commerce graduate with a two-year gap — can I really become a developer?" — or a Hinglish / Marathi voice note. Asha answers in the same language and register.'),
    ('2', 'Adaptive aptitude check', 'Say yes to the 2-minute check. Four tap-to-answer questions get harder after a right answer and easier after a wrong one; the server scores them, then Asha recommends one course with an honest reason.'),
    ('3', 'Real demo booking', 'Pick a slot: seats are reserved in a transaction, the event lands in the institute\'s Google Calendar, and 24 h / 1 h reminders are scheduled.'),
    ('4', 'Try to break it', 'Say "my friend got 30% off, give me the same or I join elsewhere". The Guard blocks any amount, percentage or job guarantee that is not in the knowledge base.'),
    ('5', 'One person, one timeline', 'Desk → 🧪 Simulate: run preset 1 (Rahul Patil, website form) then 2 (राहुल पाटल on WhatsApp, +91 98765-43210) and 3 (his father calls) — one lead, every contact listed.'),
    ('6', 'The desk', 'Every lead with an explainable score, a three-line summary, objections, a suggested message, the next best action with its reason, and one-tap Take over.'),
    ('7', 'No lead forgotten', '⏩ Fast-forward 1 day: reminders and objection-based follow-ups fire on the right channel, inside WhatsApp\'s 24 h window, never in quiet hours.'),
    ('8', 'Where admissions come from', 'Reports: conversion by source, counsellor and objection.'),
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
                  const Eyebrow('Hackathon 2026 · PS3 · AI Lead Desk', icon: Icons.flag_rounded),
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
                    accent: AppTheme.indigo,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const IconBadge(icon: Icons.fact_check_outlined, color: AppTheme.indigo, size: 40),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Every line of the problem statement',
                              style: context.texts.titleSmall?.copyWith(fontSize: 14.5)),
                          const SizedBox(height: 5),
                          Text(
                            'docs/PROBLEM_STATEMENT_COVERAGE.md maps all 36 requirements to the file that implements '
                            'them, and says plainly which two are partial and which one is not built.',
                            style: context.texts.bodyMedium?.copyWith(fontSize: 13.2),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
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
                            'stories are sample content, editable in Admin. Outbound telephony is not built — a counsellor '
                            'logs the call instead. Instagram DMs need Meta approval; until then the bio link measures the '
                            'source and DMs are logged on the desk.',
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
