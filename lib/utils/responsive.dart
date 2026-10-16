import 'package:flutter/widgets.dart';

/// Phone < 700 px, tablet 700–1100 px, desktop/web > 1100 px.
enum ScreenSize { phone, tablet, desktop }

ScreenSize screenSizeOf(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < 700) return ScreenSize.phone;
  if (w < 1100) return ScreenSize.tablet;
  return ScreenSize.desktop;
}

/// Keeps forms and chats readable on wide screens.
class MaxWidth extends StatelessWidget {
  const MaxWidth({super.key, required this.child, this.width = 720});
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width), child: child),
      );
}
