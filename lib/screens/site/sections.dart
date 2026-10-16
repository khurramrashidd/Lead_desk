import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../data/institute.dart';
import '../../utils/responsive.dart';
import '../../widgets/brand.dart';
import '../../widgets/site_widgets.dart';

// ============================================================================
// HERO
// ============================================================================
class HeroSection extends StatelessWidget {
<<<<<<< HEAD
  const HeroSection({super.key, required this.onChat, required this.onForm});
  final VoidCallback onChat;
  final VoidCallback onForm;
=======
  const HeroSection({super.key, required this.onChat, required this.onForm, required this.onCall});
  final VoidCallback onChat;
  final VoidCallback onForm;
  final VoidCallback onCall;
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)

  @override
  Widget build(BuildContext context) {
    final size = screenSizeOf(context);
    final phone = size == ScreenSize.phone;
    final copy = _copy(context, phone);

    return Section(
      gradient: AppTheme.heroGradient,
<<<<<<< HEAD
      padTop: phone ? 36 : 72,
=======
      // the fixed header sits on top of this gradient, so leave room for it
      padTop: navHeight(context) + (phone ? 28 : 52),
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
      padBottom: phone ? 48 : 88,
      child: Stack(
        children: [
          Positioned(
            right: -80,
            top: -60,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [AppTheme.amber.withValues(alpha: 0.22), Colors.transparent]),
              ),
            ),
          ),
          if (size == ScreenSize.desktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 6, child: copy),
                const SizedBox(width: 56),
                const Expanded(flex: 5, child: _ChatPreview()),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [copy, const SizedBox(height: 40), const _ChatPreview()],
            ),
        ],
      ),
    );
  }

  Widget _copy(BuildContext context, bool phone) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Eyebrow('Admissions open · Pimpri, Pune', onDark: true, icon: Icons.verified_rounded),
        const SizedBox(height: 22),
        Text(
          'Become the developer',
          style: (phone ? context.texts.displaySmall : context.texts.displayLarge)?.copyWith(color: Colors.white),
        ),
        GradientText(
          'your resume deserves.',
          style: (phone ? context.texts.displaySmall : context.texts.displayLarge) ?? const TextStyle(),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'Job-focused training in Full Stack, Data Science, DevOps and Testing — '
            'with trainers from industry, real projects, and honest counselling before you pay a rupee.',
            style: TextStyle(fontSize: phone ? 15.5 : 18, height: 1.6, color: Colors.white.withValues(alpha: 0.82)),
          ),
        ),
        const SizedBox(height: 30),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: onChat,
              icon: const Icon(Icons.auto_awesome, size: 19),
              label: const Text('Ask our AI counsellor'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.amber,
                foregroundColor: const Color(0xFF3A2606),
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onForm,
              icon: const Icon(Icons.event_available_outlined, size: 19),
              label: const Text('Book a free demo class'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
              ),
            ),
<<<<<<< HEAD
=======
            TextButton.icon(
              onPressed: onCall,
              icon: const Icon(Icons.call_outlined, size: 18),
              label: const Text('Or get a callback'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              ),
            ),
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
          ],
        ),
        const SizedBox(height: 36),
        Wrap(
          spacing: 40,
          runSpacing: 20,
          children: [for (final s in Institute.stats) StatTile(s.$1, s.$2, onDark: true)],
        ),
        const SizedBox(height: 14),
        const DemoNote('Figures are sample data for this hackathon prototype.', onDark: true),
      ],
    );
  }
}

/// A still of a real conversation Asha can hold — the product, shown in the hero.
class _ChatPreview extends StatelessWidget {
  const _ChatPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.r28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 50, offset: const Offset(0, 24))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const BrandMark(size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Asha · Admissions counsellor',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                    Row(children: [
                      Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF34D399), shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text('Online now · 11:04 PM',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11.5)),
                    ]),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _Bubble(
            fromUser: true,
            text: '🎤 व्हॉइस नोट · 0:12',
            caption: '"नमस्कार, मी कॉमर्स ग्रॅज्युएट आहे, दोन वर्षांचा गॅप आहे. मी खरंच डेव्हलपर होऊ शकते का?"',
          ),
          const SizedBox(height: 10),
          const _Bubble(
            fromUser: false,
            text: 'नमस्कार! नक्की होऊ शकता — आमच्याकडे अनेक कॉमर्स ग्रॅज्युएट्स आहेत. '
                'गॅपपेक्षा तुमची प्रोजेक्ट्स महत्त्वाची असतात. आधी Python Foundations ने सुरुवात करूया का?',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF34D399).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.4)),
                ),
                child: const Text('⚡ Replied in 4 seconds',
                    style: TextStyle(color: Color(0xFF6EE7B7), fontSize: 11.5, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('🛡 Guard checked',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.fromUser, required this.text, this.caption});
  final bool fromUser;
  final String text;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: fromUser ? AppTheme.amber.withValues(alpha: 0.92) : Colors.white.withValues(alpha: 0.13),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(fromUser ? 16 : 5),
            bottomRight: Radius.circular(fromUser ? 5 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: TextStyle(
                color: fromUser ? const Color(0xFF3A2606) : Colors.white,
                fontSize: 13.5,
                height: 1.45,
                fontWeight: fromUser ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: 4),
              Text(caption!, style: const TextStyle(color: Color(0xFF4A3208), fontSize: 12.5, height: 1.4)),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// HIRING PARTNERS STRIP
// ============================================================================
class PartnersStrip extends StatelessWidget {
  const PartnersStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Section(
      background: context.scheme.surface,
      padTop: 28,
      padBottom: 28,
      child: Column(
        children: [
          Text(
            'OUR LEARNERS HAVE BEEN PLACED WITH',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: context.scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 36,
            runSpacing: 16,
            children: [
              for (final p in Institute.hiringPartners)
                Text(
                  p,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: context.scheme.onSurface.withValues(alpha: 0.38),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const DemoNote('Partner names are fictional, created for this prototype.'),
        ],
      ),
    );
  }
}

// ============================================================================
// WHAT THE AI COUNSELLOR CHANGES  (the problem statement, answered)
// ============================================================================
class AiSection extends StatelessWidget {
  const AiSection({super.key, required this.onChat});
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    return Section(
      background: context.scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            eyebrow: 'Admissions, answered',
            title: 'Your question deserves a counsellor,\nnot a waiting queue.',
            subtitle:
                'Enquiries reach us from WhatsApp, Instagram, calls, this website and the front desk — often at midnight. '
                'Asha answers all of them in one place, in your language, and hands you to a human the moment it matters.',
          ),
          const SizedBox(height: 44),
          ResponsiveGrid(
            minItemWidth: 268,
            children: [
              for (final p in Institute.aiPromises)
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconBadge(emoji: p.$1),
                      const SizedBox(height: 18),
                      Text(p.$2, style: context.texts.titleMedium),
                      const SizedBox(height: 8),
                      Text(p.$3, style: context.texts.bodyMedium?.copyWith(fontSize: 14)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 32),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: onChat,
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('Start a conversation'),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// COURSES
// ============================================================================
class CoursesSection extends StatelessWidget {
  const CoursesSection({super.key, required this.onEnquire});
  final void Function(String courseName) onEnquire;

  @override
  Widget build(BuildContext context) {
    return Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            eyebrow: 'Programs',
            title: 'Pick the course that fits\nwhere you are today.',
            subtitle: 'Every fee below is the full fee — no registration charge, no hidden material cost. '
                'Zero-interest EMI is available on all programs.',
          ),
          const SizedBox(height: 44),
          ResponsiveGrid(
            minItemWidth: 330,
            children: [for (final c in Institute.courses) _CourseCard(course: c, onEnquire: onEnquire)],
          ),
        ],
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course, required this.onEnquire});
  final Map<String, dynamic> course;
  final void Function(String courseName) onEnquire;

  static const _tints = {
    'py': Color(0xFF0EA5E9),
    'fsj': Color(0xFF4F46E5),
    'mern': Color(0xFF059669),
    'ds': Color(0xFF7C3AED),
    'devops': Color(0xFFEA580C),
    'qa': Color(0xFFDB2777),
  };

  @override
  Widget build(BuildContext context) {
    final tint = _tints[course['id']] ?? AppTheme.indigo;
    final emi = course['emi'] as Map<String, dynamic>?;
    final name = course['name'] as String;

    return SurfaceCard(
      accent: tint,
      padding: EdgeInsets.zero,
      onTap: () => onEnquire(name),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.07),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.r20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(name, style: context.texts.titleLarge?.copyWith(height: 1.25))),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_outward_rounded, size: 20, color: tint),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _Tag('${course['durationWeeks']} weeks', tint),
                  _Tag((course['mode'] as String).split(':').first.split(' or ').first, tint),
                ]),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course['idealFor'] as String? ?? '',
                  style: context.texts.bodyMedium?.copyWith(fontSize: 14),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                Divider(color: context.scheme.outlineVariant),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rupees(course['feeInr'] as num),
                            style: context.texts.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        if (emi != null)
                          Text('or ${emi['months']} × ${rupees(emi['perMonthInr'] as num)}',
                              style: context.texts.bodySmall?.copyWith(fontSize: 12.5)),
                      ],
                    ),
                    const Spacer(),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('NEXT BATCH',
                              style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: context.scheme.onSurfaceVariant)),
                          const SizedBox(height: 2),
                          Text(
                            (course['nextBatch'] as String? ?? '').split(';').first,
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color.withValues(alpha: 0.95))),
      );
}

// ============================================================================
// WHY US
// ============================================================================
class WhyUsSection extends StatelessWidget {
  const WhyUsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Section(
      background: context.scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            eyebrow: 'Why SechTummit',
            title: 'Nine years of putting\nfreshers into real teams.',
          ),
          const SizedBox(height: 44),
          ResponsiveGrid(
            minItemWidth: 300,
            children: [
              for (final w in Institute.whyUs)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconBadge(emoji: w.$1, size: 44),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(w.$2, style: context.texts.titleSmall?.copyWith(fontSize: 15.5)),
                          const SizedBox(height: 5),
                          Text(w.$3, style: context.texts.bodyMedium?.copyWith(fontSize: 13.8)),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PLACEMENT (honest wording — the same text the AI is allowed to quote)
// ============================================================================
class PlacementSection extends StatelessWidget {
  const PlacementSection({super.key});

  @override
  Widget build(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          eyebrow: 'Placement support',
          title: 'We will not promise you a job.\nWe will make you worth hiring.',
          subtitle:
              'Any institute that guarantees a salary is guessing. Here is exactly what we do instead — and our AI counsellor '
              'is not allowed to promise you anything beyond this list.',
          onDark: true,
        ),
        const SizedBox(height: 28),
        for (final p in Institute.placementSupport)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle, size: 20, color: Color(0xFF34D399)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(p, style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 15.5, height: 1.5)),
                ),
              ],
            ),
          ),
      ],
    );

    final right = Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppTheme.r20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Icon(Icons.shield_outlined, color: AppTheme.amber, size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Our written policy',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ]),
          const SizedBox(height: 14),
          Text(
            Institute.policies['placement'] as String? ?? '',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 14.5, height: 1.6),
          ),
          const SizedBox(height: 18),
          Divider(color: Colors.white.withValues(alpha: 0.14)),
          const SizedBox(height: 14),
          Text(
            Institute.policies['refund'] as String? ?? '',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 14.5, height: 1.6),
          ),
        ],
      ),
    );

    return Section(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0B1F3A), Color(0xFF16304F)],
      ),
      child: phone
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [left, const SizedBox(height: 32), right])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Expanded(flex: 6, child: left), const SizedBox(width: 48), Expanded(flex: 5, child: right)],
            ),
    );
  }
}

// ============================================================================
// UPCOMING BATCHES
// ============================================================================
class BatchesSection extends StatelessWidget {
  const BatchesSection({super.key, required this.onEnquire});
  final void Function(String courseName) onEnquire;

  @override
  Widget build(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
    return Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            eyebrow: 'Upcoming batches',
            title: 'Seats open this month.',
            subtitle: 'Every batch starts with a free demo class. Attend it before you decide — parents are welcome.',
          ),
          const SizedBox(height: 36),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < Institute.courses.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: context.scheme.outlineVariant),
                  _BatchRow(course: Institute.courses[i], phone: phone, onEnquire: onEnquire),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchRow extends StatelessWidget {
  const _BatchRow({required this.course, required this.phone, required this.onEnquire});
  final Map<String, dynamic> course;
  final bool phone;
  final void Function(String courseName) onEnquire;

  @override
  Widget build(BuildContext context) {
    final name = course['name'] as String;
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name, style: context.texts.titleSmall?.copyWith(fontSize: 15)),
        const SizedBox(height: 3),
        Text(
          '${course['nextBatch']} · ${course['durationWeeks']} weeks',
          style: context.texts.bodySmall?.copyWith(fontSize: 12.8),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: 12),
                Row(children: [
                  Text(rupees(course['feeInr'] as num), style: context.texts.titleSmall),
                  const Spacer(),
                  OutlinedButton(onPressed: () => onEnquire(name), child: const Text('Enquire')),
                ]),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 5, child: info),
                Expanded(
                  flex: 2,
                  child: Text(rupees(course['feeInr'] as num), style: context.texts.titleSmall),
                ),
                OutlinedButton(onPressed: () => onEnquire(name), child: const Text('Enquire')),
              ],
            ),
    );
  }
}

// ============================================================================
// STUDENT STORIES
// ============================================================================
class StoriesSection extends StatelessWidget {
  const StoriesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Section(
      background: context.scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            eyebrow: 'Student stories',
            title: 'The gap on your resume\nis not the end of the story.',
          ),
          const SizedBox(height: 14),
          const DemoNote('Illustrative stories written for this prototype, not real student quotes.'),
          const SizedBox(height: 36),
          ResponsiveGrid(
            minItemWidth: 320,
            children: [
              for (final s in Institute.stories)
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('"', style: TextStyle(fontSize: 46, height: 0.9, fontWeight: FontWeight.w800, color: AppTheme.amber.withValues(alpha: 0.6))),
                      Text(s.$3, style: context.texts.bodyLarge?.copyWith(fontSize: 15, height: 1.6)),
                      const SizedBox(height: 20),
                      Row(children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: AppTheme.indigo.withValues(alpha: 0.14),
                          child: Text(s.$1.substring(0, 1),
                              style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.indigo)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.$1, style: context.texts.titleSmall?.copyWith(fontSize: 14)),
                              Text(s.$2, style: context.texts.bodySmall?.copyWith(fontSize: 12.5)),
                            ],
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// FAQ
// ============================================================================
class FaqSection extends StatelessWidget {
<<<<<<< HEAD
  const FaqSection({super.key, required this.onChat});
  final VoidCallback onChat;
=======
  const FaqSection({super.key, required this.onChat, required this.onCall});
  final VoidCallback onChat;
  final VoidCallback onCall;
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)

  @override
  Widget build(BuildContext context) {
    final faqs = <(String, String)>[
      for (final f in Institute.faqs) (f['q'] as String, f['a'] as String),
      ('Can I pay in instalments?', Institute.policies['emi'] as String? ?? ''),
      ('What if I miss a class?', Institute.policies['recordings'] as String? ?? ''),
      ('Is there a discount?', Institute.policies['discounts'] as String? ?? ''),
      ('How do the batches run?', Institute.policies['batches'] as String? ?? ''),
    ];

    return Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            eyebrow: 'Questions',
            title: 'Asked before you ask.',
            subtitle: 'Anything else? Asha answers from exactly this information — never more.',
          ),
          const SizedBox(height: 36),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: Column(
                children: [
                  for (var i = 0; i < faqs.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: context.scheme.outlineVariant),
                    ExpansionTile(
                      shape: const RoundedRectangleBorder(side: BorderSide.none),
                      collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
                      childrenPadding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      title: Text(faqs[i].$1, style: context.texts.titleSmall?.copyWith(fontSize: 15)),
                      children: [Text(faqs[i].$2, style: context.texts.bodyMedium?.copyWith(fontSize: 14.5))],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
<<<<<<< HEAD
          TextButton.icon(
            onPressed: onChat,
            icon: const Icon(Icons.auto_awesome, size: 17),
            label: const Text('Ask something else'),
          ),
=======
          Wrap(spacing: 10, runSpacing: 10, children: [
            TextButton.icon(
              onPressed: onChat,
              icon: const Icon(Icons.auto_awesome, size: 17),
              label: const Text('Ask something else'),
            ),
            TextButton.icon(
              onPressed: onCall,
              icon: const Icon(Icons.call_outlined, size: 17),
              label: const Text('Talk to a human instead'),
            ),
          ]),
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
        ],
      ),
    );
  }
}

// ============================================================================
// CLOSING CTA
// ============================================================================
class CtaSection extends StatelessWidget {
<<<<<<< HEAD
  const CtaSection({super.key, required this.onChat, required this.onForm});
  final VoidCallback onChat;
  final VoidCallback onForm;
=======
  const CtaSection({super.key, required this.onChat, required this.onForm, required this.onCall});
  final VoidCallback onChat;
  final VoidCallback onForm;
  final VoidCallback onCall;
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)

  @override
  Widget build(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
    return Section(
      padTop: phone ? 48 : 72,
      padBottom: phone ? 48 : 72,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: phone ? 26 : 56, vertical: phone ? 36 : 56),
        decoration: BoxDecoration(
          gradient: AppTheme.brandGradient,
          borderRadius: BorderRadius.circular(AppTheme.r28),
          boxShadow: [BoxShadow(color: AppTheme.indigo.withValues(alpha: 0.3), blurRadius: 50, offset: const Offset(0, 20))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BrandMark(size: 44, tile: false, color: Colors.white, inkColor: AppTheme.indigoDeep),
            const SizedBox(height: 22),
            Text(
              'Still deciding? Ask the hard question.',
              style: (phone ? context.texts.headlineSmall : context.texts.headlineLarge)?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Text(
                '"Will I get a job?" "Is my gap too long?" "Can I afford this?" — Asha answers honestly, in your language, '
                'any time of day, and books your free demo class on the spot.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: phone ? 15 : 16.5, height: 1.6),
              ),
            ),
            const SizedBox(height: 28),
            Wrap(spacing: 12, runSpacing: 12, children: [
              FilledButton.icon(
                onPressed: onChat,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Chat with Asha'),
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppTheme.indigoDeep),
              ),
              OutlinedButton.icon(
                onPressed: onForm,
                icon: const Icon(Icons.edit_note, size: 19),
                label: const Text('Send an enquiry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.45)),
                ),
              ),
<<<<<<< HEAD
=======
              OutlinedButton.icon(
                onPressed: onCall,
                icon: const Icon(Icons.videocam_outlined, size: 19),
                label: const Text('Book a call or video meeting'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.45)),
                ),
              ),
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
            ]),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// FOOTER
// ============================================================================
class SiteFooter extends StatelessWidget {
  const SiteFooter({super.key, required this.onNavigate});
  final void Function(String route) onNavigate;

  @override
  Widget build(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
    final columns = <Widget>[
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const InstituteLogo(size: 34, onDark: true),
          const SizedBox(height: 16),
          Text(Institute.tagline,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.62), fontSize: 13.5, height: 1.6)),
          const SizedBox(height: 16),
          _FooterLine(Icons.location_on_outlined, Institute.address),
          _FooterLine(Icons.call_outlined, Institute.phone),
          _FooterLine(Icons.mail_outline, Institute.email),
        ],
      ),
      _FooterColumn('Programs', [for (final c in Institute.courses.take(5)) (c['name'] as String, null)]),
      _FooterColumn('Institute', const [
        ('Placement support', null),
        ('Fees and EMI', null),
        ('Refund policy', null),
        ('Contact us', null),
      ]),
      _FooterColumn('For our team', [
        ('Counsellor desk', () => onNavigate('/desk')),
        ('Admin console', () => onNavigate('/admin')),
        ('Walk-in entry', () => onNavigate('/walkin')),
        ('Demo hub (judges)', () => onNavigate('/demo')),
      ]),
    ];

    return Container(
      width: double.infinity,
      color: AppTheme.navy,
      padding: SitePadding.of(context).copyWith(top: 56, bottom: 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (phone)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final c in columns) Padding(padding: const EdgeInsets.only(bottom: 30), child: c),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: columns[0]),
                    const SizedBox(width: 32),
                    Expanded(flex: 3, child: columns[1]),
                    Expanded(flex: 3, child: columns[2]),
                    Expanded(flex: 3, child: columns[3]),
                  ],
                ),
              const SizedBox(height: 36),
              Divider(color: Colors.white.withValues(alpha: 0.12)),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 10,
                spacing: 16,
                children: [
                  Text('© ${DateTime.now().year} ${Institute.name}. Prototype built for Kurukshetra 2026.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12.5)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Powered by', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12.5)),
                      const SizedBox(width: 8),
                      const LeadDeskLogo(size: 20, onDark: true),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterLine extends StatelessWidget {
  const _FooterLine(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.45)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.62), fontSize: 13)),
          ),
        ]),
      );
}

class _FooterColumn extends StatelessWidget {
  const _FooterColumn(this.title, this.links);
  final String title;
  final List<(String, VoidCallback?)> links;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95), fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
          const SizedBox(height: 14),
          for (final l in links)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: l.$2,
                child: Text(l.$1,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: l.$2 == null ? 0.6 : 0.8),
                      fontSize: 13.5,
                      decoration: l.$2 == null ? null : TextDecoration.underline,
                      decorationColor: Colors.white24,
                    )),
              ),
            ),
        ],
      );
}
