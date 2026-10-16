import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../data/institute.dart';
import '../../utils/responsive.dart';
import '../../widgets/brand.dart';
import '../../widgets/site_widgets.dart';
import '../chat/prospect_chat_screen.dart';
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
  bool _scrolled = false;
  bool _chatOpen = false;

  @override
  void initState() {
    super.initState();
    _chatOpen = widget.openChat;
    _scroll.addListener(() {
      final s = _scroll.offset > 12;
      if (s != _scrolled) setState(() => _scrolled = s);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _goTo(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 520), curve: Curves.easeInOutCubic);
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
    Navigator.of(context).pushNamed('/form${course == null ? '' : '?src=${widget.source}'}');
  }

  @override
  Widget build(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
    return Scaffold(
      backgroundColor: context.scheme.surface,
      endDrawer: phone ? _MobileMenu(onJump: _jump, onChat: _openChat) : null,
      body: Stack(
        children: [
          Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              child: Column(
                children: [
                  SizedBox(height: phone ? 64 : 76),
                  HeroSection(onChat: _openChat, onForm: _openForm),
                  const PartnersStrip(),
                  AiSection(onChat: _openChat),
                  Container(key: _courses, child: CoursesSection(onEnquire: _openForm)),
                  const WhyUsSection(),
                  Container(key: _placement, child: const PlacementSection()),
                  Container(key: _batches, child: BatchesSection(onEnquire: _openForm)),
                  const StoriesSection(),
                  Container(key: _faq, child: FaqSection(onChat: _openChat)),
                  CtaSection(onChat: _openChat, onForm: _openForm),
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
          if (!(_chatOpen && !phone))
            Positioned(right: phone ? 16 : 24, bottom: phone ? 16 : 24, child: _ChatLauncher(onTap: _openChat)),
        ],
      ),
    );
  }

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
          foregroundColor: onDark ? Colors.white.withValues(alpha: 0.9) : context.scheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        child: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
      );
}

class _MobileMenu extends StatelessWidget {
  const _MobileMenu({required this.onJump, required this.onChat});
  final void Function(String) onJump;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    void go(String t) {
      Navigator.of(context).pop();
      Future<void>.delayed(const Duration(milliseconds: 120), () => onJump(t));
    }

    return Drawer(
      child: SafeArea(
        child: ListView(
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
              onPressed: () {
                Navigator.of(context).pop();
                onChat();
              },
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Talk to our counsellor'),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('${Institute.phone}\n${Institute.address}',
                  style: context.texts.bodySmall?.copyWith(fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- chat launcher
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
                child: Text('Ask in हिंदी, मराठी or English',
                    style: context.texts.bodySmall?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ),
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) => Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.indigo.withValues(alpha: 0.25 + 0.2 * _pulse.value),
                    blurRadius: 18 + 14 * _pulse.value,
                    spreadRadius: 1 + 3 * _pulse.value,
                  ),
                ],
              ),
              child: child,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: const BoxDecoration(gradient: AppTheme.brandGradient, shape: BoxShape.circle),
                  child: const Center(
                    child: BrandMark(size: 34, tile: false, color: Colors.white, inkColor: AppTheme.indigoDeep),
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
class _ChatDock extends StatelessWidget {
  const _ChatDock({required this.source, required this.onClose});
  final String source;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      width: 404,
      height: (h * 0.78).clamp(460.0, 680.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.r20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 48, offset: const Offset(0, 20))],
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
