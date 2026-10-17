import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../data/institute.dart';
import '../../l10n.dart';
import '../../utils/responsive.dart';
import '../../widgets/brand.dart';
import '../../widgets/site_widgets.dart';

// =========================================================================== hero
class HeroSection extends StatelessWidget {
  const HeroSection({super.key, required this.onChat, required this.onForm, required this.onCall});
  final VoidCallback onChat;
  final VoidCallback onForm;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final size = screenSizeOf(context);
    final phone = size == ScreenSize.phone;
    final wide = size == ScreenSize.desktop;
    final titleStyle = (phone ? context.texts.displaySmall : context.texts.displayMedium)?.copyWith(color: Colors.white, fontSize: phone ? 34 : (wide ? 56 : 46));

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(tr('hero.eyebrow'), onDark: true, icon: Icons.location_on_rounded),
        const SizedBox(height: 22),
        Text(tr('hero.title1'), style: titleStyle),
        GradientText(tr('hero.title2'), style: titleStyle ?? const TextStyle(fontSize: 46, fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            tr('hero.sub'),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: phone ? 15.5 : 17.5, height: 1.6),
          ),
        ),
        const SizedBox(height: 30),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: onChat,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(tr('hero.chat')),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.coral, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18)),
            ),
            OutlinedButton.icon(
              onPressed: onCall,
              icon: const Icon(Icons.support_agent_rounded, size: 18),
              label: Text(tr('hero.call')),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              ),
            ),
            TextButton(
              onPressed: onForm,
              style: TextButton.styleFrom(foregroundColor: Colors.white70, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18)),
              child: Text('${tr('hero.form')} →'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 20,
          runSpacing: 10,
          children: [
            for (final k in ['hero.trust1', 'hero.trust2', 'hero.trust3'])
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.check_circle_rounded, size: 17, color: Color(0xFF5EEAD4)),
                const SizedBox(width: 7),
                Text(tr(k), style: const TextStyle(color: Colors.white70, fontSize: 13.5, fontWeight: FontWeight.w600)),
              ]),
          ],
        ),
      ],
    );

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
      child: Stack(
        children: [
          const Positioned.fill(child: _HeroGlow()),
          Padding(
            padding: SitePadding.of(context).copyWith(top: navHeight(context) + (phone ? 36 : 72), bottom: phone ? 56 : 96),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: wide
                    ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                        Expanded(flex: 6, child: copy),
                        const SizedBox(width: 56),
                        const Expanded(flex: 5, child: _ChatPreview()),
                      ])
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        copy,
                        if (!phone) ...[const SizedBox(height: 44), const _ChatPreview()],
                      ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft teal and coral light behind the hero.
class _HeroGlow extends StatelessWidget {
  const _HeroGlow();

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Stack(children: [
          Positioned(
            right: -120,
            top: -80,
            child: Container(
              width: 520,
              height: 520,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [const Color(0xFF14B8A6).withValues(alpha: 0.28), Colors.transparent]),
              ),
            ),
          ),
          Positioned(
            left: -160,
            bottom: -200,
            child: Container(
              width: 520,
              height: 520,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [AppTheme.coral.withValues(alpha: 0.18), Colors.transparent]),
              ),
            ),
          ),
        ]),
      );
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
              color: me ? AppTheme.indigo : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(me ? 16 : 4),
                bottomRight: Radius.circular(me ? 4 : 16),
              ),
            ),
            child: Text(text, style: TextStyle(color: me ? Colors.white : AppTheme.ink, fontSize: 13.8, height: 1.45)),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppTheme.r28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 60, offset: const Offset(0, 30))],
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
                Text('Asha', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                Text('online · 11:42 PM', style: TextStyle(color: Colors.white60, fontSize: 11.5)),
              ]),
            ),
            _Pill('EN · हिं · मरा', color: const Color(0xFF5EEAD4)),
          ]),
          const SizedBox(height: 16),
          bubble(tr('hero.card.q'), me: true),
          bubble(tr('hero.card.a'), me: false),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Pill('🧠 Aptitude 3/4', color: const Color(0xFFC4B5FD)),
            _Pill('🛡 No invented fees', color: const Color(0xFFFCA5A5)),
            _Pill('📅 Demo booked', color: const Color(0xFF86EFAC)),
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
  const CoursesSection({super.key, required this.kb, required this.onAsk, required this.onEnquire});
  final Kb kb;
  final void Function(String? prefill) onAsk;
  final VoidCallback onEnquire;

  static const _accents = [AppTheme.indigo, AppTheme.coral, AppTheme.ai, AppTheme.human, Color(0xFF0891B2), Color(0xFFD97706)];
  static const _icons = [Icons.code_rounded, Icons.coffee_rounded, Icons.web_rounded, Icons.insights_rounded, Icons.cloud_rounded, Icons.bug_report_rounded];

  @override
  Widget build(BuildContext context) {
    final courses = kb.courses;
    return Section(
      background: context.scheme.surfaceContainerLow,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader(eyebrow: tr('courses.eyebrow'), title: tr('courses.title'), subtitle: tr('courses.sub')),
        const SizedBox(height: 36),
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
    final wide = screenSizeOf(context) != ScreenSize.phone;
    final policy = '${kb.policies['placement'] ?? ''}';
    final left = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(eyebrow: tr('placement.eyebrow'), title: tr('placement.title'), onDark: true),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppTheme.r16),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.verified_user_rounded, color: Color(0xFF5EEAD4), size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(policy, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.6))),
        ]),
      ),
    ]);
    final right = Column(children: [
      for (final p in Institute.placementSupport)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(AppTheme.r16),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(children: [
            const Icon(Icons.check_rounded, color: AppTheme.coral),
            const SizedBox(width: 12),
            Expanded(child: Text(p, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600))),
          ]),
        ),
    ]);
    return Section(
      gradient: AppTheme.heroGradient,
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: left), const SizedBox(width: 48), Expanded(child: right)])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [left, const SizedBox(height: 28), right]),
    );
  }
}

// =================================================================== batches
class BatchesSection extends StatelessWidget {
  const BatchesSection({super.key, required this.kb, required this.onBook});
  final Kb kb;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final batches = '${kb.policies['batches'] ?? ''}';
    return Section(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader(eyebrow: tr('batches.eyebrow'), title: tr('batches.title'), subtitle: batches.isEmpty ? null : batches),
        const SizedBox(height: 28),
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
                child: Row(children: [
                  Expanded(flex: 5, child: Text('${kb.courses[i]['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                  Expanded(
                    flex: 6,
                    child: Row(children: [
                      Icon(Icons.event_available_rounded, size: 16, color: AppTheme.indigo),
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
  const FaqSection({super.key, required this.kb, required this.onChat, required this.onCall});
  final Kb kb;
  final VoidCallback onChat;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final faqs = kb.faqs;
    return Section(
      maxWidth: 880,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader(eyebrow: tr('faq.eyebrow'), title: tr('faq.title')),
        const SizedBox(height: 26),
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

// ======================================================================= CTA
class CtaSection extends StatelessWidget {
  const CtaSection({super.key, required this.onChat, required this.onForm, required this.onCall});
  final VoidCallback onChat;
  final VoidCallback onForm;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
    return Section(
      padTop: phone ? 30 : 60,
      padBottom: phone ? 40 : 80,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(phone ? 26 : 48),
        decoration: BoxDecoration(gradient: AppTheme.coralGradient, borderRadius: BorderRadius.circular(AppTheme.r28)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('cta.title'), style: (phone ? context.texts.headlineSmall : context.texts.headlineLarge)?.copyWith(color: Colors.white)),
          const SizedBox(height: 10),
          Text(tr('cta.sub'), style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5)),
          const SizedBox(height: 24),
          Wrap(spacing: 12, runSpacing: 12, children: [
            FilledButton.icon(
              onPressed: onChat,
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppTheme.amberDeep),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(tr('hero.chat')),
            ),
            OutlinedButton.icon(
              onPressed: onCall,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
              icon: const Icon(Icons.call_rounded, size: 18),
              label: Text(tr('hero.call')),
            ),
            TextButton(onPressed: onForm, style: TextButton.styleFrom(foregroundColor: Colors.white), child: Text('${tr('hero.form')} →')),
          ]),
        ]),
      ),
    );
  }
}

// ==================================================================== footer
class SiteFooter extends StatelessWidget {
  const SiteFooter({super.key, required this.onNavigate});
  final void Function(String route) onNavigate;

  @override
  Widget build(BuildContext context) {
    final linkStyle = TextButton.styleFrom(foregroundColor: Colors.white70, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8));
    return Section(
      background: AppTheme.ink,
      padTop: 48,
      padBottom: 40,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
          spacing: 40,
          runSpacing: 24,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const InstituteLogo(size: 34, onDark: true),
                const SizedBox(height: 14),
                Text(Institute.tagline, style: const TextStyle(color: Colors.white70, height: 1.5)),
                const SizedBox(height: 10),
                Text('${Institute.phone} · ${Institute.email}\n${Institute.address}', style: const TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.6)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('ENQUIRE', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              TextButton(style: linkStyle, onPressed: () => onNavigate('/chat?src=footer'), child: const Text('Web chat')),
              TextButton(style: linkStyle, onPressed: () => onNavigate('/form?src=form'), child: const Text('Enquiry form')),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('STAFF', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              TextButton(style: linkStyle, onPressed: () => onNavigate('/desk'), child: const Text('Counsellor desk')),
              TextButton(style: linkStyle, onPressed: () => onNavigate('/walkin'), child: const Text('Walk-in counter')),
              TextButton(style: linkStyle, onPressed: () => onNavigate('/demo'), child: const Text('Demo hub (judges)')),
            ]),
          ],
        ),
        const SizedBox(height: 28),
        const Divider(color: Colors.white12),
        const SizedBox(height: 14),
        Row(children: [
          const LeadDeskLogo(size: 22, onDark: true),
          const SizedBox(width: 10),
          Expanded(child: Text('© ${DateTime.now().year} · ${tr('sample.note')}', style: const TextStyle(color: Colors.white38, fontSize: 11.5))),
        ]),
      ]),
    );
  }
}
