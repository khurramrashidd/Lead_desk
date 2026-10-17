import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../l10n.dart';

/// EN | हिं | मरा segmented switch. Changes the website and chat texts; Asha always mirrors
/// the language the prospect actually writes in.
class LangSwitch extends StatelessWidget {
  const LangSwitch({super.key, this.onDark = false});
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLang>(
      valueListenable: L10n.lang,
      builder: (context, current, _) => _build(context, current),
    );
  }

  Widget _build(BuildContext context, AppLang current) {
    final fg = onDark ? Colors.white : context.scheme.onSurface;
    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.10) : context.scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: onDark ? Colors.white24 : context.scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final l in AppLang.values)
            GestureDetector(
              onTap: () => L10n.set(l),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: l == current ? (onDark ? Colors.white : AppTheme.ink) : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  L10n.label(l),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: l == current ? (onDark ? AppTheme.ink : Colors.white) : fg.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact language picker for narrow screens: "EN ▾" opens English / हिंदी / मराठी.
class LangMenuButton extends StatelessWidget {
  const LangMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLang>(
      valueListenable: L10n.lang,
      builder: (context, current, _) => PopupMenuButton<AppLang>(
        tooltip: 'Language',
        initialValue: current,
        onSelected: L10n.set,
        position: PopupMenuPosition.under,
        itemBuilder: (_) => [
          for (final l in AppLang.values)
            PopupMenuItem(
              value: l,
              child: Row(children: [
                Icon(l == current ? Icons.check_rounded : Icons.translate_rounded, size: 18, color: l == current ? AppTheme.indigo : null),
                const SizedBox(width: 10),
                Text(L10n.name(l), style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
        ],
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: context.scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: context.scheme.outlineVariant),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.translate_rounded, size: 16, color: context.scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(L10n.label(current), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: context.scheme.onSurface)),
            Icon(Icons.arrow_drop_down_rounded, size: 18, color: context.scheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}
