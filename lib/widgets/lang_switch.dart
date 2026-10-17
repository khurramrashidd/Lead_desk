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
