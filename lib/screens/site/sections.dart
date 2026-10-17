import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../data/institute.dart';
import '../../l10n.dart';
import '../../utils/responsive.dart';
import '../../data/links.dart';
import '../../widgets/brand.dart';
import '../../widgets/channel_links.dart';
import '../../widgets/site_widgets.dart';
import 'site_screen.dart' show SitePage;

// =========================================================================== hero
/// Home: one headline, one line, and the three ways to start (Asha, WhatsApp, Telegram).
class HomeHero extends StatelessWidget {
  const HomeHero({super.key, required this.onChat, required this.onCall});
  final VoidCallback onChat;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final size = screenSizeOf(context);
    final phone = size == ScreenSize.phone;
    final wide = size == ScreenSize.desktop;
    final dark = context.isDark;
    final titleStyle = (phone ? context.texts.headlineLarge : context.texts.displayMedium)?.copyWith(
      color: context.scheme.onSurface,
      fontSize: phone ? 31 : (wide ? 54 : 44),
    );

    final buttons = phone
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilledButton.icon(
              onPressed: onChat,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(tr('hero.chat')),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.coral, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(52)),
            ),
            const SizedBox(height: 10),
            const Row(children: [
              Expanded(child: TalkButton(ChatChannel.whatsapp, compact: true)),
              SizedBox(width: 10),
              Expanded(child: TalkButton(ChatChannel.telegram, compact: true)),
            ]),
          ])
        : Wrap(spacing: 12, runSpacing: 12, children: [
            FilledButton.icon(
              onPressed: onChat,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(tr('hero.chat')),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.coral, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18)),
            ),
            const TalkButton(ChatChannel.whatsapp),
            const TalkButton(ChatChannel.telegram),
          ]);

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(tr('hero.eyebrow'), icon: Icons.location_on_rounded),
        SizedBox(height: phone ? 16 : 22),
        Text(tr('hero.title1'), style: titleStyle),
        GradientText(
          tr('hero.title2'),
          style: titleStyle ?? const TextStyle(fontSize: 44, fontWeight: FontWeight.w800),
          gradient: LinearGradient(colors: dark ? const [Color(0xFF5EEAD4), Color(0xFFFF8A6B)] : const [AppTheme.indigo, AppTheme.coral]),
        ),
        SizedBox(height: phone ? 12 : 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(tr('hero.short'), style: context.texts.bodyLarge?.copyWith(fontSize: phone ? 15.5 : 17.5, color: context.scheme.onSurfaceVariant)),
        ),
        SizedBox(height: phone ? 22 : 30),
        buttons,
        const SizedBox(height: 12),
        Wrap(spacing: 4, runSpacing: 0, crossAxisAlignment: WrapCrossAlignment.center, children: [
          TextButton.icon(
            onPressed: onCall,
            icon: const Icon(Icons.support_agent_rounded, size: 17),
            label: Text(tr('hero.call')),
          ),
          TextButton.icon(
            onPressed: () => openChannel(context, ChatChannel.form),
            icon: const Icon(Icons.assignment_outlined, size: 17),
            label: Text(tr('hero.form')),
          ),
        ]),
        if (!phone) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 18, runSpacing: 8, children: [
            for (final k in ['hero.trust1', 'hero.trust2', 'hero.trust3'])
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.success),
                const SizedBox(width: 6),
                Text(tr(k), style: TextStyle(color: context.scheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
          ]),
        ],
      ],
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark ? const [Color(0xFF0B1220), Color(0xFF0E2A2A)] : const [Color(0xFFEFF8F6), Color(0xFFFFFFFF), Color(0xFFFFF4EF)],
        ),
      ),
      padding: SitePadding.of(context).copyWith(top: phone ? 28 : 64, bottom: phone ? 34 : 72),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(flex: 6, child: copy),
                  const SizedBox(width: 56),
                  const Expanded(flex: 5, child: _ChatPreview()),
                ])
              : copy,
        ),
      ),
    );
  }
}

/// Scan-to-chat: QR codes for WhatsApp, Telegram and the Google Form (judges scan from the screen).
class ScanToChatSection extends StatefulWidget {
  const ScanToChatSection({super.key, required this.onChat});
  final VoidCallback onChat;

  @override
  State<ScanToChatSection> createState() => _ScanToChatSectionState();
}

class _ScanToChatSectionState extends State<ScanToChatSection> {
  bool _showQr = false;

  @override
  Widget build(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
    final cards = ResponsiveGrid(
      minItemWidth: 240,
      children: const [ChannelQrCard(ChatChannel.whatsapp), ChannelQrCard(ChatChannel.telegram), ChannelQrCard(ChatChannel.form)],
    );
    return Section(
      background: context.scheme.surfaceContainerLow,
      padTop: phone ? 30 : 64,
      padBottom: phone ? 30 : 64,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader(eyebrow: tr('scan.eyebrow'), title: tr('scan.title'), subtitle: tr(phone ? 'scan.subPhone' : 'scan.sub')),
        SizedBox(height: phone ? 18 : 30),
        if (!phone)
          cards
        else ...[
          // On the phone itself a QR is not scannable: show one-tap buttons, QR on request.
          for (final c in ChatChannel.values) _ChannelTile(c),
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _showQr = !_showQr),
              icon: Icon(_showQr ? Icons.expand_less_rounded : Icons.qr_code_2, size: 18),
              label: Text(tr(_showQr ? 'scan.hideQr' : 'scan.showQr')),
            ),
          ),
          if (_showQr) cards,
        ],
      ]),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile(this.channel);
  final ChatChannel channel;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: context.scheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.r16),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.r16),
            onTap: () => openChannel(context, channel),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.r16),
                border: Border.all(color: channel.color.withValues(alpha: 0.35)),
              ),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: channel.color, borderRadius: BorderRadius.circular(12)),
                  child: Icon(channel.icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(channel.talkLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    ValueListenableBuilder<PublicLinks>(
                      valueListenable: PublicLinks.current,
                      builder: (context, l, _) => Text(channel.handle(l), style: context.texts.bodySmall?.copyWith(fontSize: 12.5)),
                    ),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: channel.color),
              ]),
            ),
          ),
        ),
      );
}

/// Home: the course list in one glance (full details live on the Courses page).
class HomeCourses extends StatelessWidget {
  const HomeCourses({super.key, required this.kb, required this.onAsk, required this.onAll});
  final Kb kb;
  final void Function(String? prefill) onAsk;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
    return Section(
      padTop: phone ? 30 : 64,
      padBottom: phone ? 34 : 72,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: SectionHeader(eyebrow: tr('courses.eyebrow'), title: tr('home.courses'))),
          if (!phone) TextButton(onPressed: onAll, child: Text('${tr('home.allCourses')} →')),
        ]),
        SizedBox(height: phone ? 16 : 26),
        ResponsiveGrid(
          minItemWidth: 340,
          spacing: 12,
          children: [for (final c in kb.courses) _CourseRow(c: c, onAsk: onAsk)],
        ),
        if (phone) ...[
          const SizedBox(height: 8),
          Center(child: TextButton(onPressed: onAll, child: Text('${tr('home.allCourses')} →'))),
        ],
      ]),
    );
  }
}

class _CourseRow extends StatelessWidget {
  const _CourseRow({required this.c, required this.onAsk});
  final Map<String, dynamic> c;
  final void Function(String? prefill) onAsk;

  @override
  Widget build(BuildContext context) {
    final name = '${c['name'] ?? ''}';
    final fee = c['feeInr'] as num?;
    return Material(
      color: context.scheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.r16),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.r16),
        onTap: () => onAsk('${tr('courses.tell')} $name'),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppTheme.r16), border: Border.all(color: context.scheme.outlineVariant)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  [
                    '${c['durationWeeks'] ?? '-'} ${tr('courses.weeks')}',
                    if (fee != null) rupees(fee),
                    if ((c['nextBatch'] as String?)?.isNotEmpty == true) '${tr('courses.next')}: ${c['nextBatch']}',
                  ].join(' · '),
                  style: context.texts.bodySmall?.copyWith(fontSize: 12.5),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppTheme.indigo.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.auto_awesome, size: 14, color: AppTheme.indigo),
                const SizedBox(width: 5),
                Text(tr('courses.askShort'), style: const TextStyle(color: AppTheme.indigo, fontWeight: FontWeight.w800, fontSize: 12.5)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Heading of an inner page (Courses, FAQ, …).
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
    return Container(
      width: double.infinity,
      color: context.scheme.surfaceContainerLow,
      padding: SitePadding.of(context).copyWith(top: phone ? 22 : 40, bottom: phone ? 18 : 30),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Text(title, style: (phone ? context.texts.headlineSmall : context.texts.headlineLarge)?.copyWith(color: context.scheme.onSurface)),
        ),
      ),
    );
  }
}

/// Contact page: address, phone, and every way to reach a counsellor.
class ContactSection extends StatelessWidget {
  const ContactSection({super.key, required this.onChat, required this.onCall});
  final VoidCallback onChat;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Section(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SurfaceCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(Institute.name, style: context.texts.titleLarge),
            const SizedBox(height: 6),
            Text('${Institute.address}\n${Institute.phone} · ${Institute.email}', style: context.texts.bodyMedium?.copyWith(height: 1.7)),
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 10, children: [
              FilledButton.icon(
                onPressed: onChat,
                style: FilledButton.styleFrom(backgroundColor: AppTheme.coral, foregroundColor: Colors.white),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(tr('hero.chat')),
              ),
              OutlinedButton.icon(onPressed: onCall, icon: const Icon(Icons.support_agent_rounded, size: 18), label: Text(tr('hero.call'))),
            ]),
          ]),
        ),
        const SizedBox(height: 26),
        Text(tr('scan.title'), style: context.texts.titleLarge),
        const SizedBox(height: 14),
        const ResponsiveGrid(
          minItemWidth: 240,
          children: [ChannelQrCard(ChatChannel.whatsapp), ChannelQrCard(ChatChannel.telegram), ChannelQrCard(ChatChannel.form)],
        ),
      ]),
    );
  }
}

/// A still of the real product: the sponsor's exact example question, answered.
class _ChatPreview extends StatelessWidget {
  const _ChatPreview();

  @override
  Widget build(BuildContext context) {
    Widget bubble(String text, {required bool me}) => Align(
          alignment: me ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            decoration: BoxDecoration(
              color: me ? AppTheme.indigo : context.scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(me ? 16 : 4),
                bottomRight: Radius.circular(me ? 4 : 16),
              ),
            ),
            child: Text(text, style: TextStyle(color: me ? Colors.white : context.scheme.onSurface, fontSize: 13.8, height: 1.45)),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.r28),
        border: Border.all(color: context.scheme.outlineVariant),
        boxShadow: AppTheme.lift(context, y: 24, blur: 50, opacity: 0.10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: const BoxDecoration(gradient: AppTheme.brandGradient, shape: BoxShape.circle),
              child: const Text('अ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Asha', style: TextStyle(fontWeight: FontWeight.w800)),
                Text('online · 11:42 PM', style: TextStyle(color: AppTheme.success, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ]),
            ),
            _Pill('EN · हिं · मरा', color: AppTheme.indigo),
          ]),
          const SizedBox(height: 16),
          bubble(tr('hero.card.q'), me: true),
          bubble(tr('hero.card.a'), me: false),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Pill('🧠 Aptitude 3/4', color: AppTheme.ai),
            _Pill('🛡 No invented fees', color: AppTheme.guard),
            _Pill('📅 Demo booked', color: AppTheme.success),
          ]),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );
}

// ===================================================================== stats
class StatsStrip extends StatelessWidget {
  const StatsStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Section(
      padTop: 34,
      padBottom: 34,
      background: context.scheme.surfaceContainerLow,
      child: Column(children: [
        ResponsiveGrid(
          minItemWidth: 200,
          children: [for (final s in Institute.stats) StatTile(s.$1, s.$2)],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 22,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final p in Institute.hiringPartners)
              Text(p, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: context.scheme.onSurfaceVariant.withValues(alpha: 0.7), letterSpacing: -0.2)),
          ],
        ),
        const SizedBox(height: 10),
        DemoNote(tr('sample.note')),
      ]),
    );
  }
}

// ======================================================================== AI
class AiSection extends StatelessWidget {
  const AiSection({super.key, required this.onChat});
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.nightlight_round, AppTheme.indigo, 'ai.p1.t', 'ai.p1.d'),
      (Icons.translate_rounded, AppTheme.coral, 'ai.p2.t', 'ai.p2.d'),
      (Icons.psychology_rounded, AppTheme.ai, 'ai.p3.t', 'ai.p3.d'),
      (Icons.verified_user_rounded, AppTheme.human, 'ai.p4.t', 'ai.p4.d'),
    ];
    return Section(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader(eyebrow: tr('ai.eyebrow'), title: tr('ai.title'), subtitle: tr('ai.sub')),
        const SizedBox(height: 36),
        ResponsiveGrid(
          minItemWidth: 250,
          children: [
            for (final i in items)
              SurfaceCard(
                onTap: onChat,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  IconBadge(icon: i.$1, color: i.$2, size: 46),
                  const SizedBox(height: 18),
                  Text(tr(i.$3), style: context.texts.titleMedium),
                  const SizedBox(height: 8),
                  Text(tr(i.$4), style: context.texts.bodyMedium?.copyWith(fontSize: 14)),
                ]),
              ),
          ],
        ),
      ]),
    );
  }
}

// =================================================================== courses
class CoursesSection extends StatelessWidget {
  const CoursesSection({super.key, required this.kb, required this.onAsk, required this.onEnquire, this.showHeader = true});
  final Kb kb;
  final void Function(String? prefill) onAsk;
  final VoidCallback onEnquire;
  final bool showHeader;

  static const _accents = [AppTheme.indigo, AppTheme.coral, AppTheme.ai, AppTheme.human, Color(0xFF0891B2), Color(0xFFD97706)];
  static const _icons = [Icons.code_rounded, Icons.coffee_rounded, Icons.web_rounded, Icons.insights_rounded, Icons.cloud_rounded, Icons.bug_report_rounded];

  @override
  Widget build(BuildContext context) {
    final courses = kb.courses;
    final phone = screenSizeOf(context) == ScreenSize.phone;
    return Section(
      padTop: showHeader ? null : (phone ? 22 : 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showHeader) ...[
          SectionHeader(eyebrow: tr('courses.eyebrow'), title: tr('courses.title'), subtitle: tr('courses.sub')),
          const SizedBox(height: 36),
        ] else ...[
          Text(tr('courses.sub'), style: context.texts.bodyLarge?.copyWith(color: context.scheme.onSurfaceVariant)),
          const SizedBox(height: 20),
        ],
        ResponsiveGrid(
          minItemWidth: 330,
          children: [
            for (var i = 0; i < courses.length; i++) _CourseCard(c: courses[i], accent: _accents[i % _accents.length], icon: _icons[i % _icons.length], onAsk: onAsk, onEnquire: onEnquire),
          ],
        ),
      ]),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.c, required this.accent, required this.icon, required this.onAsk, required this.onEnquire});
  final Map<String, dynamic> c;
  final Color accent;
  final IconData icon;
  final void Function(String? prefill) onAsk;
  final VoidCallback onEnquire;

  @override
  Widget build(BuildContext context) {
    final emi = (c['emi'] as Map?)?.cast<String, dynamic>();
    final fee = c['feeInr'] as num?;
    final name = '${c['name'] ?? ''}';
    return SurfaceCard(
      padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconBadge(icon: icon, color: accent, size: 44),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: context.scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(999)),
            child: Text('${c['durationWeeks'] ?? '-'} ${tr('courses.weeks')}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 16),
        Text(name, style: context.texts.titleLarge?.copyWith(fontSize: 19)),
        const SizedBox(height: 6),
        Text('${c['mode'] ?? ''}', style: context.texts.bodySmall?.copyWith(fontSize: 12.5)),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(fee == null ? '—' : rupees(fee), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: context.scheme.onSurface)),
          const SizedBox(width: 10),
          if (emi != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${tr('courses.emi')} ${emi['months']} × ${rupees(emi['perMonthInr'] as num? ?? 0)}', style: TextStyle(fontSize: 12.5, color: accent, fontWeight: FontWeight.w700)),
            ),
        ]),
        const SizedBox(height: 14),
        if ((c['idealFor'] as String?)?.isNotEmpty == true)
          Text('${tr('courses.idealFor')}: ${c['idealFor']}', style: context.texts.bodyMedium?.copyWith(fontSize: 13.5)),
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.event_rounded, size: 15, color: context.scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(child: Text('${tr('courses.next')}: ${c['nextBatch'] ?? '—'}', style: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: () => onAsk('${tr('courses.ask')} — $name'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Text(tr('courses.ask'), overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onEnquire,
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16)),
            child: Text(tr('courses.enquire')),
          ),
        ]),
      ]),
    );
  }
}

// ==================================================================== why us
class WhyUsSection extends StatelessWidget {
  const WhyUsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Section(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader(eyebrow: tr('why.eyebrow'), title: tr('why.title')),
        const SizedBox(height: 34),
        ResponsiveGrid(
          minItemWidth: 320,
          children: [
            for (final w in Institute.whyUs)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                IconBadge(emoji: w.$1, size: 44, color: AppTheme.indigo),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(w.$2, style: context.texts.titleMedium),
                    const SizedBox(height: 6),
                    Text(w.$3, style: context.texts.bodyMedium?.copyWith(fontSize: 14)),
                  ]),
                ),
              ]),
          ],
        ),
      ]),
    );
  }
}

// ================================================================= placement
class PlacementSection extends StatelessWidget {
  const PlacementSection({super.key, required this.kb});
  final Kb kb;

  @override
  Widget build(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
    final policy = '${kb.policies['placement'] ?? ''}';
    final left = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(eyebrow: tr('placement.eyebrow'), title: tr('placement.title')),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.indigo.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppTheme.r16),
          border: Border.all(color: AppTheme.indigo.withValues(alpha: 0.25)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.verified_user_rounded, color: AppTheme.indigo, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(policy, style: context.texts.bodyLarge?.copyWith(fontSize: 15, color: context.scheme.onSurface))),
        ]),
      ),
    ]);
    final right = Column(children: [
      for (final p in Institute.placementSupport)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: context.scheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.r16),
            border: Border.all(color: context.scheme.outlineVariant),
          ),
          child: Row(children: [
            const Icon(Icons.check_rounded, color: AppTheme.coral),
            const SizedBox(width: 12),
            Expanded(child: Text(p, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600))),
          ]),
        ),
    ]);
    return Section(
      padTop: phone ? 26 : 56,
      child: !phone
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: left), const SizedBox(width: 48), Expanded(child: right)])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [left, const SizedBox(height: 24), right]),
    );
  }
}

// =================================================================== batches
class BatchesSection extends StatelessWidget {
  const BatchesSection({super.key, required this.kb, required this.onBook, this.showHeader = true});
  final Kb kb;
  final VoidCallback onBook;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final batches = '${kb.policies['batches'] ?? ''}';
    final phone = screenSizeOf(context) == ScreenSize.phone;
    return Section(
      padTop: showHeader ? null : (phone ? 22 : 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showHeader)
          SectionHeader(eyebrow: tr('batches.eyebrow'), title: tr('batches.title'), subtitle: batches.isEmpty ? null : batches)
        else if (batches.isNotEmpty)
          Text(batches, style: context.texts.bodyLarge?.copyWith(color: context.scheme.onSurfaceVariant)),
        const SizedBox(height: 22),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.r20),
            border: Border.all(color: context.scheme.outlineVariant),
          ),
          child: Column(children: [
            for (var i = 0; i < kb.courses.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: phone
                    ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${kb.courses[i]['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.event_available_rounded, size: 16, color: AppTheme.indigo),
                          const SizedBox(width: 8),
                          Expanded(child: Text('${kb.courses[i]['nextBatch'] ?? '—'}', style: context.texts.bodyMedium?.copyWith(fontSize: 14))),
                        ]),
                      ])
                    : Row(children: [
                        Expanded(flex: 5, child: Text('${kb.courses[i]['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                        Expanded(
                          flex: 6,
                          child: Row(children: [
                            const Icon(Icons.event_available_rounded, size: 16, color: AppTheme.indigo),
                            const SizedBox(width: 8),
                            Expanded(child: Text('${kb.courses[i]['nextBatch'] ?? '—'}', style: context.texts.bodyMedium?.copyWith(fontSize: 14))),
                          ]),
                        ),
                      ]),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onBook,
          style: FilledButton.styleFrom(backgroundColor: AppTheme.coral),
          icon: const Icon(Icons.event_rounded, size: 18),
          label: Text(tr('chat.s4')),
        ),
      ]),
    );
  }
}

// =================================================================== stories
class StoriesSection extends StatelessWidget {
  const StoriesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Section(
      background: context.scheme.surfaceContainerLow,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader(eyebrow: tr('stories.eyebrow'), title: tr('stories.title')),
        const SizedBox(height: 32),
        ResponsiveGrid(
          minItemWidth: 320,
          children: [
            for (final s in Institute.stories)
              SurfaceCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.format_quote_rounded, color: AppTheme.coral, size: 30),
                  const SizedBox(height: 8),
                  Text(s.$3, style: context.texts.bodyLarge?.copyWith(fontSize: 15)),
                  const SizedBox(height: 18),
                  Row(children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppTheme.indigo.withValues(alpha: 0.12),
                      child: Text(s.$1.substring(0, 1), style: const TextStyle(color: AppTheme.indigo, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.$1, style: context.texts.titleSmall),
                        Text(s.$2, style: context.texts.bodySmall?.copyWith(fontSize: 12)),
                      ]),
                    ),
                  ]),
                ]),
              ),
          ],
        ),
        const SizedBox(height: 14),
        DemoNote(tr('sample.note')),
      ]),
    );
  }
}

// ======================================================================= FAQ
class FaqSection extends StatelessWidget {
  const FaqSection({super.key, required this.kb, required this.onChat, required this.onCall, this.showHeader = true});
  final Kb kb;
  final VoidCallback onChat;
  final VoidCallback onCall;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final faqs = kb.faqs;
    final phone = screenSizeOf(context) == ScreenSize.phone;
    return Section(
      maxWidth: 880,
      padTop: showHeader ? null : (phone ? 22 : 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showHeader) ...[
          SectionHeader(eyebrow: tr('faq.eyebrow'), title: tr('faq.title')),
          const SizedBox(height: 26),
        ],
        for (final f in faqs)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.r16),
              border: Border.all(color: context.scheme.outlineVariant),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.r16)),
                title: Text('${f['q']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                children: [Align(alignment: Alignment.centerLeft, child: Text('${f['a']}', style: context.texts.bodyMedium?.copyWith(fontSize: 14.5)))],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(onPressed: onChat, icon: const Icon(Icons.auto_awesome, size: 17), label: Text(tr('faq.more'))),
          OutlinedButton.icon(onPressed: onCall, icon: const Icon(Icons.support_agent_rounded, size: 17), label: Text(tr('hero.call'))),
        ]),
      ]),
    );
  }
}

// ==================================================================== footer
/// Light, short footer on every page.
class SiteFooter extends StatelessWidget {
  const SiteFooter({super.key, required this.onNavigate, required this.onPage});
  final void Function(String route) onNavigate;
  final void Function(SitePage page) onPage;

  @override
  Widget build(BuildContext context) {
    final linkStyle = TextButton.styleFrom(
      foregroundColor: context.scheme.onSurfaceVariant,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: context.scheme.outlineVariant)),
      ),
      padding: SitePadding.of(context).copyWith(top: 28, bottom: 90),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InstituteLogo(size: 30, onDark: context.isDark),
            const SizedBox(height: 10),
            Text('${Institute.tagline}\n${Institute.phone} · ${Institute.email}', style: context.texts.bodySmall?.copyWith(fontSize: 12.5, height: 1.6)),
            const SizedBox(height: 10),
            Wrap(spacing: 2, runSpacing: 0, children: [
              TextButton(style: linkStyle, onPressed: () => onPage(SitePage.courses), child: Text(tr('nav.courses'))),
              TextButton(style: linkStyle, onPressed: () => onPage(SitePage.faq), child: Text(tr('nav.faq'))),
              TextButton(style: linkStyle, onPressed: () => onPage(SitePage.contact), child: Text(tr('nav.contact'))),
              TextButton(style: linkStyle, onPressed: () => onNavigate('/desk'), child: Text(tr('menu.staff'))),
              TextButton(style: linkStyle, onPressed: () => onNavigate('/demo'), child: Text(tr('menu.judges'))),
            ]),
            const SizedBox(height: 6),
            DemoNote(tr('sample.note')),
          ]),
        ),
      ),
    );
  }
}
