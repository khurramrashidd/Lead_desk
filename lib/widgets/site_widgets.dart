import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/responsive.dart';

<<<<<<< HEAD
=======
/// Height of the fixed site header. The hero adds this to its own top padding
/// so the dark gradient runs underneath the bar — otherwise the bar's white
/// logo would sit on the white page background and vanish.
double navHeight(BuildContext context) => screenSizeOf(context) == ScreenSize.phone ? 62 : 74;

>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
/// Horizontal rhythm for the whole public site.
class SitePadding {
  static EdgeInsets of(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 700) return const EdgeInsets.symmetric(horizontal: 20);
    if (w < 1100) return const EdgeInsets.symmetric(horizontal: 40);
    return const EdgeInsets.symmetric(horizontal: 64);
  }

  static double vertical(BuildContext context) => screenSizeOf(context) == ScreenSize.phone ? 56 : 104;
}

/// A full-width band with a centred, max-width column inside.
class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.child,
    this.background,
    this.gradient,
    this.maxWidth = 1180,
    this.padTop,
    this.padBottom,
  });

  final Widget child;
  final Color? background;
  final Gradient? gradient;
  final double maxWidth;
  final double? padTop;
  final double? padBottom;

  @override
  Widget build(BuildContext context) {
    final v = SitePadding.vertical(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: background, gradient: gradient),
      padding: SitePadding.of(context).copyWith(top: padTop ?? v, bottom: padBottom ?? v),
      child: Center(
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      ),
    );
  }
}

/// Eyebrow + headline + optional sub-line, used above every section.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.onDark = false,
    this.center = false,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final bool onDark;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
    final strong = onDark ? Colors.white : context.scheme.onSurface;
    final soft = onDark ? Colors.white70 : context.scheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Eyebrow(eyebrow, onDark: onDark),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: (phone ? context.texts.headlineSmall : context.texts.headlineLarge)?.copyWith(color: strong),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Text(
              subtitle!,
              textAlign: center ? TextAlign.center : TextAlign.start,
              style: context.texts.bodyLarge?.copyWith(color: soft, fontSize: phone ? 15 : 17),
            ),
          ),
        ],
      ],
    );
  }
}

/// Small capsule label above a headline.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.onDark = false, this.icon});
  final String text;
  final bool onDark;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? const Color(0xFFFBBF24) : AppTheme.indigo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: onDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 6)],
          Text(
            text.toUpperCase(),
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: fg),
          ),
        ],
      ),
    );
  }
}

/// Responsive equal-width grid that never leaves an awkward last row.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.minItemWidth = 300, this.spacing = 20});
  final List<Widget> children;
  final double minItemWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final columns = (c.maxWidth / minItemWidth).floor().clamp(1, 4);
      final width = (c.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final child in children) SizedBox(width: width, child: child)],
      );
    });
  }
}

/// Bordered surface used for every card on the site.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.onTap,
    this.accent,
    this.lifted = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? accent;
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.scheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.r20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.r20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.r20),
            border: Border.all(
              color: accent?.withValues(alpha: 0.35) ?? context.scheme.outlineVariant,
            ),
            boxShadow: lifted ? AppTheme.lift(context) : null,
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// A big number with a caption. Works on light and dark bands.
class StatTile extends StatelessWidget {
  const StatTile(this.value, this.label, {super.key, this.onDark = false});
  final String value;
  final String label;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            color: onDark ? Colors.white : context.scheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: onDark ? Colors.white70 : context.scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Square icon badge in a soft tint — used on feature and course cards.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, this.emoji, this.icon, this.color, this.size = 48});
  final String? emoji;
  final IconData? icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.indigo;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: c.withValues(alpha: 0.22)),
      ),
      child: emoji != null
          ? Text(emoji!, style: TextStyle(fontSize: size * 0.46))
          : Icon(icon, size: size * 0.5, color: c),
    );
  }
}

/// Honest labelling for prototype content, so nothing reads as a real claim.
class DemoNote extends StatelessWidget {
  const DemoNote(this.text, {super.key, this.onDark = false});
  final String text;
  final bool onDark;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 14, color: onDark ? Colors.white54 : context.scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: onDark ? Colors.white54 : context.scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
}

/// Formats 65000 as "₹65,000" in the Indian digit grouping.
String rupees(num value) {
  final s = value.round().toString();
  if (s.length <= 3) return '₹$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final buf = <String>[];
  while (rest.length > 2) {
    buf.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) buf.insert(0, rest);
  return '₹${buf.join(',')},$last3';
}
