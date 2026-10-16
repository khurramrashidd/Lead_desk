<<<<<<< HEAD
=======
import 'dart:ui' show ImageFilter;

>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../data/institute.dart';
<<<<<<< HEAD
=======
import '../../main.dart';
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
import '../../utils/responsive.dart';
import '../../widgets/brand.dart';
import '../../widgets/site_widgets.dart';
import '../chat/prospect_chat_screen.dart';
<<<<<<< HEAD
=======
import 'book_call_sheet.dart';
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
import 'sections.dart';

/// The SechTummit Trainers public website — what a prospective student lands on.
/// The AI counsellor lives in the corner of it, which is the whole point of PS3:
/// the enquiry is answered where it arrives.
class SiteScreen extends StatefulWidget {
  const SiteScreen({super.key, this.source = 'web', this.openChat = false});
  final String source;
  final bool openChat;

  @override
  State<SiteScreen> createState() => _SiteScreenState();
}

class _SiteScreenState extends State<SiteScreen> {
  final _scroll = ScrollController();
  final _courses = GlobalKey();
  final _batches = GlobalKey();
  final _placement = GlobalKey();
  final _faq = GlobalKey();
<<<<<<< HEAD
=======

>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
  bool _scrolled = false;
  bool _chatOpen = false;

  @override
  void initState() {
    super.initState();
    _chatOpen = widget.openChat;
<<<<<<< HEAD
    _scroll.addListener(() {
      final s = _scroll.offset > 12;
      if (s != _scrolled) setState(() => _scrolled = s);
    });
=======
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final s = _scroll.hasClients && _scroll.offset > 18;
    if (s != _scrolled) setState(() => _scrolled = s);
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
  }

  @override
  void dispose() {
<<<<<<< HEAD
=======
    _scroll.removeListener(_onScroll);
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _goTo(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
<<<<<<< HEAD
    await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 520), curve: Curves.easeInOutCubic);
=======
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubic,
      alignment: 0.02,
    );
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
  }

  void _openChat() {
    if (screenSizeOf(context) == ScreenSize.phone) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProspectChatScreen(source: widget.source)),
      );
    } else {
      setState(() => _chatOpen = true);
    }
  }

  void _openForm([String? course]) {
<<<<<<< HEAD
    Navigator.of(context).pushNamed('/form${course == null ? '' : '?src=${widget.source}'}');
=======
    Navigator.of(context).pushNamed('/form?src=${widget.source}');
  }

  void _bookCall() => showBookCallSheet(context, source: widget.source);

  void _jump(String target) {
    switch (target) {
      case 'courses':
        _goTo(_courses);
      case 'batches':
        _goTo(_batches);
      case 'placement':
        _goTo(_placement);
      case 'faq':
        _goTo(_faq);
      case 'top':
        _scroll.animateTo(0, duration: const Duration(milliseconds: 420), curve: Curves.easeInOutCubic);
      case 'desk':
        Navigator.of(context).pushNamed('/desk');
      case 'demo':
        Navigator.of(context).pushNamed('/demo');
    }
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
  }

  @override
  Widget build(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
<<<<<<< HEAD
    return Scaffold(
      backgroundColor: context.scheme.surface,
      endDrawer: phone ? _MobileMenu(onJump: _jump, onChat: _openChat) : null,
=======
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: context.scheme.surface,
      endDrawer: phone ? _MobileMenu(onJump: _jump, onChat: _openChat, onCall: _bookCall) : null,
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
      body: Stack(
        children: [
          Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              child: Column(
                children: [
<<<<<<< HEAD
                  SizedBox(height: phone ? 64 : 76),
                  HeroSection(onChat: _openChat, onForm: _openForm),
=======
                  // No spacer: the hero's own padding clears the nav, so the dark
                  // gradient sits behind it and the white logo stays readable.
                  HeroSection(onChat: _openChat, onForm: _openForm, onCall: _bookCall),
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
                  const PartnersStrip(),
                  AiSection(onChat: _openChat),
                  Container(key: _courses, child: CoursesSection(onEnquire: _openForm)),
                  const WhyUsSection(),
                  Container(key: _placement, child: const PlacementSection()),
                  Container(key: _batches, child: BatchesSection(onEnquire: _openForm)),
                  const StoriesSection(),
<<<<<<< HEAD
                  Container(key: _faq, child: FaqSection(onChat: _openChat)),
                  CtaSection(onChat: _openChat, onForm: _openForm),
=======
                  Container(key: _faq, child: FaqSection(onChat: _openChat, onCall: _bookCall)),
                  CtaSection(onChat: _openChat, onForm: _openForm, onCall: _bookCall),
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
                  SiteFooter(onNavigate: (r) => Navigator.of(context).pushNamed(r)),
                ],
              ),
            ),
          ),
          _TopNav(scrolled: _scrolled, onJump: _jump, onChat: _openChat),
          if (!phone && _chatOpen)
            Positioned(
              right: 24,
              bottom: 24,
              child: _ChatDock(source: widget.source, onClose: () => setState(() => _chatOpen = false)),
            ),
<<<<<<< HEAD
          if (!(_chatOpen && !phone))
            Positioned(right: phone ? 16 : 24, bottom: phone ? 16 : 24, child: _ChatLauncher(onTap: _openChat)),
=======
          if (phone || !_chatOpen)
            Positioned(
              right: phone ? 16 : 24,
              bottom: (phone ? 16 : 24) + bottomInset,
              child: _ChatLauncher(onTap: _openChat),
            ),
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
        ],
      ),
    );
  }
<<<<<<< HEAD

  void _jump(String target) {
    switch (target) {
      case 'courses':
        _goTo(_courses);
      case 'batches':
        _goTo(_batches);
      case 'placement':
        _goTo(_placement);
      case 'faq':
        _goTo(_faq);
      case 'desk':
        Navigator.of(context).pushNamed('/desk');
    }
  }
=======
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
}

// ---------------------------------------------------------------- top nav bar
class _TopNav extends StatelessWidget {
  const _TopNav({required this.scrolled, required this.onJump, required this.onChat});
  final bool scrolled;
  final void Function(String) onJump;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
<<<<<<< HEAD
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      height: phone ? 64 : 76,
      decoration: BoxDecoration(
        color: scrolled ? context.scheme.surface.withValues(alpha: 0.96) : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: scrolled ? context.scheme.outlineVariant : Colors.transparent,
          ),
        ),
      ),
      padding: SitePadding.of(context),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Row(
            children: [
              InkWell(
                onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
                child: InstituteLogo(size: phone ? 30 : 34, onDark: !scrolled),
              ),
              const Spacer(),
              if (!phone) ...[
                _NavLink('Courses', () => onJump('courses'), onDark: !scrolled),
                _NavLink('Batches', () => onJump('batches'), onDark: !scrolled),
                _NavLink('Placement', () => onJump('placement'), onDark: !scrolled),
                _NavLink('FAQ', () => onJump('faq'), onDark: !scrolled),
                const SizedBox(width: 10),
                TextButton.icon(
                  onPressed: () => onJump('desk'),
                  icon: const Icon(Icons.lock_outline, size: 15),
                  label: const Text('Staff'),
                  style: TextButton.styleFrom(
                    foregroundColor: scrolled ? context.scheme.onSurfaceVariant : Colors.white70,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onChat,
                  icon: const Icon(Icons.auto_awesome, size: 17),
                  label: const Text('Talk to counsellor'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                    backgroundColor: scrolled ? AppTheme.indigo : AppTheme.amber,
                    foregroundColor: scrolled ? Colors.white : const Color(0xFF3A2606),
                  ),
                ),
              ] else
                Builder(
                  builder: (context) => IconButton(
                    onPressed: () => Scaffold.of(context).openEndDrawer(),
                    icon: Icon(Icons.menu_rounded, color: scrolled ? context.scheme.onSurface : Colors.white),
                  ),
                ),
            ],
          ),
        ),
=======
    final h = navHeight(context);
    // Over the dark hero the bar is see-through with white text; once the page
    // scrolls it becomes a solid, blurred bar with dark text. Either way the
    // contrast is deliberate — never white on white.
    final onDark = !scrolled;

    return Align(
      alignment: Alignment.topCenter,
      child: ClipRect(
        child: BackdropFilter(
          filter: scrolled ? ImageFilter.blur(sigmaX: 14, sigmaY: 14) : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            height: h,
            decoration: BoxDecoration(
              color: scrolled ? context.scheme.surface.withValues(alpha: 0.88) : Colors.transparent,
              border: Border(
                bottom: BorderSide(color: scrolled ? context.scheme.outlineVariant : Colors.transparent),
              ),
              boxShadow: scrolled
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 18, offset: const Offset(0, 4))]
                  : null,
            ),
            padding: SitePadding.of(context),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => onJump('top'),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                        child: InstituteLogo(size: phone ? 28 : 33, onDark: onDark, compact: phone),
                      ),
                    ),
                    const Spacer(),
                    if (!phone) ...[
                      _NavLink('Courses', () => onJump('courses'), onDark: onDark),
                      _NavLink('Batches', () => onJump('batches'), onDark: onDark),
                      _NavLink('Placement', () => onJump('placement'), onDark: onDark),
                      _NavLink('FAQ', () => onJump('faq'), onDark: onDark),
                      const SizedBox(width: 6),
                      _ThemeToggle(onDark: onDark),
                      IconButton(
                        tooltip: 'Staff sign in',
                        onPressed: () => onJump('desk'),
                        icon: Icon(Icons.lock_outline_rounded,
                            size: 19, color: onDark ? Colors.white70 : context.scheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: onChat,
                        icon: const Icon(Icons.auto_awesome, size: 17),
                        label: const Text('Talk to counsellor'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                          backgroundColor: onDark ? AppTheme.amber : AppTheme.indigo,
                          foregroundColor: onDark ? const Color(0xFF3A2606) : Colors.white,
                        ),
                      ),
                    ] else ...[
                      _ThemeToggle(onDark: onDark),
                      Builder(
                        builder: (context) => IconButton(
                          tooltip: 'Menu',
                          onPressed: () => Scaffold.of(context).openEndDrawer(),
                          icon: Icon(Icons.menu_rounded,
                              color: onDark ? Colors.white : context.scheme.onSurface),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({required this.onDark});
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return IconButton(
      tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
      onPressed: () => LeadDeskApp.themeMode.value = dark ? ThemeMode.light : ThemeMode.dark,
      icon: Icon(
        dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        size: 19,
        color: onDark ? Colors.white70 : context.scheme.onSurfaceVariant,
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink(this.label, this.onTap, {this.onDark = false});
  final String label;
  final VoidCallback onTap;
  final bool onDark;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
<<<<<<< HEAD
          foregroundColor: onDark ? Colors.white.withValues(alpha: 0.9) : context.scheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
=======
          foregroundColor: onDark ? Colors.white : context.scheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
        ),
        child: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
      );
}

class _MobileMenu extends StatelessWidget {
<<<<<<< HEAD
  const _MobileMenu({required this.onJump, required this.onChat});
  final void Function(String) onJump;
  final VoidCallback onChat;
=======
  const _MobileMenu({required this.onJump, required this.onChat, required this.onCall});
  final void Function(String) onJump;
  final VoidCallback onChat;
  final VoidCallback onCall;
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)

  @override
  Widget build(BuildContext context) {
    void go(String t) {
      Navigator.of(context).pop();
<<<<<<< HEAD
      Future<void>.delayed(const Duration(milliseconds: 120), () => onJump(t));
=======
      Future<void>.delayed(const Duration(milliseconds: 140), () => onJump(t));
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
    }

    return Drawer(
      child: SafeArea(
        child: ListView(
<<<<<<< HEAD
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(padding: EdgeInsets.only(left: 8, bottom: 18), child: InstituteLogo(size: 34)),
            ListTile(leading: const Icon(Icons.school_outlined), title: const Text('Courses'), onTap: () => go('courses')),
            ListTile(leading: const Icon(Icons.event_outlined), title: const Text('Batches'), onTap: () => go('batches')),
            ListTile(leading: const Icon(Icons.work_outline), title: const Text('Placement'), onTap: () => go('placement')),
            ListTile(leading: const Icon(Icons.help_outline), title: const Text('FAQ'), onTap: () => go('faq')),
            const Divider(height: 28),
            ListTile(leading: const Icon(Icons.lock_outline), title: const Text('Staff sign in'), onTap: () => go('desk')),
            const SizedBox(height: 16),
            FilledButton.icon(
=======
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(8, 6, 8, 16), child: InstituteLogo(size: 34)),
            _tile(context, Icons.school_outlined, 'Courses', () => go('courses')),
            _tile(context, Icons.event_outlined, 'Batches', () => go('batches')),
            _tile(context, Icons.work_outline, 'Placement', () => go('placement')),
            _tile(context, Icons.help_outline, 'FAQ', () => go('faq')),
            const Divider(height: 26),
            _tile(context, Icons.lock_outline, 'Staff sign in', () => go('desk')),
            _tile(context, Icons.science_outlined, 'Demo hub (judges)', () => go('demo')),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
              onPressed: () {
                Navigator.of(context).pop();
                onChat();
              },
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Talk to our counsellor'),
            ),
<<<<<<< HEAD
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('${Institute.phone}\n${Institute.address}',
                  style: context.texts.bodySmall?.copyWith(fontSize: 12.5)),
=======
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: () {
                Navigator.of(context).pop();
                onCall();
              },
              icon: const Icon(Icons.call_outlined, size: 18),
              label: const Text('Request a callback'),
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${Institute.phone}\n${Institute.address}',
                style: context.texts.bodySmall?.copyWith(fontSize: 12.5, height: 1.6),
              ),
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
            ),
          ],
        ),
      ),
    );
  }
<<<<<<< HEAD
}

// ------------------------------------------------------------- chat launcher
=======

  Widget _tile(BuildContext context, IconData icon, String label, VoidCallback onTap) => ListTile(
        leading: Icon(icon, size: 21),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.r12)),
        onTap: onTap,
      );
}

// -------------------------------------------------------------- chat launcher
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
class _ChatLauncher extends StatefulWidget {
  const _ChatLauncher({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_ChatLauncher> createState() => _ChatLauncherState();
}

class _ChatLauncherState extends State<_ChatLauncher> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  bool _hover = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
<<<<<<< HEAD
=======
    final size = phone ? 58.0 : 62.0;
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!phone)
            AnimatedOpacity(
              opacity: _hover ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: context.scheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.r12),
                  border: AppTheme.hairline(context),
                  boxShadow: AppTheme.lift(context, y: 6, blur: 18),
                ),
<<<<<<< HEAD
                child: Text('Ask in हिंदी, मराठी or English',
                    style: context.texts.bodySmall?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600)),
=======
                child: Text(
                  'Ask in हिंदी, मराठी or English',
                  style: context.texts.bodySmall?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
              ),
            ),
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) => Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
<<<<<<< HEAD
                    color: AppTheme.indigo.withValues(alpha: 0.25 + 0.2 * _pulse.value),
                    blurRadius: 18 + 14 * _pulse.value,
                    spreadRadius: 1 + 3 * _pulse.value,
=======
                    color: AppTheme.indigo.withValues(alpha: 0.22 + 0.18 * _pulse.value),
                    blurRadius: 16 + 12 * _pulse.value,
                    spreadRadius: 1 + 2.5 * _pulse.value,
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
                  ),
                ],
              ),
              child: child,
            ),
            child: Material(
              color: Colors.transparent,
<<<<<<< HEAD
              child: InkWell(
                onTap: widget.onTap,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: const BoxDecoration(gradient: AppTheme.brandGradient, shape: BoxShape.circle),
                  child: const Center(
                    child: BrandMark(size: 34, tile: false, color: Colors.white, inkColor: AppTheme.indigoDeep),
=======
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTap,
                child: Container(
                  width: size,
                  height: size,
                  decoration: const BoxDecoration(gradient: AppTheme.brandGradient, shape: BoxShape.circle),
                  child: Center(
                    child: BrandMark(
                      size: size * 0.55,
                      tile: false,
                      color: Colors.white,
                      inkColor: AppTheme.indigoDeep,
                    ),
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Desktop/tablet: the chat opens as a panel over the page, like a real site widget.
<<<<<<< HEAD
=======
/// It is clamped to the viewport so it can never hang off the screen.
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
class _ChatDock extends StatelessWidget {
  const _ChatDock({required this.source, required this.onClose});
  final String source;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
<<<<<<< HEAD
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      width: 404,
      height: (h * 0.78).clamp(460.0, 680.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.r20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 48, offset: const Offset(0, 20))],
=======
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 48).clamp(300.0, 404.0);
    final height = (size.height - 120).clamp(380.0, 660.0);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.r20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.26), blurRadius: 44, offset: const Offset(0, 18))],
>>>>>>> e64e53d (fix: repair escaped interpolation in callback card, clear all analyzer issues)
      ),
      clipBehavior: Clip.antiAlias,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.r20),
        border: AppTheme.hairline(context),
      ),
      child: ProspectChatScreen(source: source, embedded: true, onClose: onClose),
    );
  }
}
