import 'dart:ui' show ImageFilter;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../data/institute.dart';
import '../../l10n.dart';
import '../../main.dart';
import '../../services/repo.dart';
import '../../utils/responsive.dart';
import '../../widgets/brand.dart';
import '../../widgets/lang_switch.dart';
import '../../widgets/site_widgets.dart';
import '../chat/prospect_chat_screen.dart';
import 'book_call_sheet.dart';
import 'sections.dart';

/// The SechTummit Trainers public website: what a prospective student lands on.
/// The AI counsellor lives in the corner of it, which is the whole point of PS3:
/// the enquiry is answered where it arrives, at any hour, in their language.
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
  String? _prefill;

  @override
  void initState() {
    super.initState();
    _chatOpen = widget.openChat;
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final s = _scroll.hasClients && _scroll.offset > 18;
    if (s != _scrolled) setState(() => _scrolled = s);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _goTo(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 520), curve: Curves.easeInOutCubic, alignment: 0.02);
  }

  void _openChat([String? prefill]) {
    if (screenSizeOf(context) == ScreenSize.phone) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProspectChatScreen(source: widget.source, prefill: prefill)));
    } else {
      setState(() {
        _prefill = prefill;
        _chatOpen = true;
      });
    }
  }

  void _openForm([String? course]) => Navigator.of(context).pushNamed('/form?src=${widget.source}');

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
  }

  @override
  Widget build(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return ValueListenableBuilder<AppLang>(
      valueListenable: L10n.lang,
      builder: (context, _, _) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: Repo.watchKb(),
        builder: (context, snap) {
          final kb = Kb.from(snap.data?.data());
          return Scaffold(
            backgroundColor: context.scheme.surface,
            endDrawer: phone ? _MobileMenu(onJump: _jump, onChat: () => _openChat(), onCall: _bookCall) : null,
            body: Stack(
              children: [
                Scrollbar(
                  controller: _scroll,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    child: Column(
                      children: [
                        HeroSection(onChat: () => _openChat(), onForm: () => _openForm(), onCall: _bookCall),
                        const StatsStrip(),
                        AiSection(onChat: () => _openChat()),
                        Container(key: _courses, child: CoursesSection(kb: kb, onAsk: _openChat, onEnquire: _openForm)),
                        const WhyUsSection(),
                        Container(key: _placement, child: PlacementSection(kb: kb)),
                        Container(key: _batches, child: BatchesSection(kb: kb, onBook: () => _openChat(tr('chat.s4')))),
                        const StoriesSection(),
                        Container(key: _faq, child: FaqSection(kb: kb, onChat: () => _openChat(), onCall: _bookCall)),
                        CtaSection(onChat: () => _openChat(), onForm: () => _openForm(), onCall: _bookCall),
                        SiteFooter(onNavigate: (r) => Navigator.of(context).pushNamed(r)),
                      ],
                    ),
                  ),
                ),
                _TopNav(scrolled: _scrolled, onJump: _jump, onChat: () => _openChat()),
                if (!phone && _chatOpen)
                  Positioned(
                    right: 24,
                    bottom: 24,
                    child: _ChatDock(
                      key: ValueKey(_prefill),
                      source: widget.source,
                      prefill: _prefill,
                      onClose: () => setState(() => _chatOpen = false),
                    ),
                  ),
                if (phone || !_chatOpen)
                  Positioned(
                    right: phone ? 16 : 24,
                    bottom: (phone ? 16 : 24) + bottomInset,
                    child: _ChatLauncher(onTap: () => _openChat()),
                  ),
              ],
            ),
          );
        },
      ),
    );
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
    final size = screenSizeOf(context);
    final phone = size == ScreenSize.phone;
    final h = navHeight(context);
    // Over the dark hero the bar is see-through with white text; once the page scrolls it
    // becomes a solid, blurred bar. In dark mode the bar is dark either way.
    final onDark = !scrolled || context.isDark;

    return Align(
      alignment: Alignment.topCenter,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: scrolled ? 14 : 0, sigmaY: scrolled ? 14 : 0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            height: h,
            decoration: BoxDecoration(
              color: scrolled ? context.scheme.surface.withValues(alpha: 0.9) : Colors.transparent,
              border: Border(bottom: BorderSide(color: scrolled ? context.scheme.outlineVariant : Colors.transparent)),
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
                        child: InstituteLogo(size: phone ? 28 : 32, onDark: onDark, compact: phone),
                      ),
                    ),
                    const Spacer(),
                    if (size == ScreenSize.desktop) ...[
                      _NavLink(tr('nav.courses'), () => onJump('courses'), onDark: onDark),
                      _NavLink(tr('nav.batches'), () => onJump('batches'), onDark: onDark),
                      _NavLink(tr('nav.placement'), () => onJump('placement'), onDark: onDark),
                      _NavLink(tr('nav.faq'), () => onJump('faq'), onDark: onDark),
                      const SizedBox(width: 8),
                    ],
                    LangSwitch(onDark: onDark),
                    if (!phone) ...[
                      _ThemeToggle(onDark: onDark),
                      IconButton(
                        tooltip: 'Staff sign in',
                        onPressed: () => onJump('desk'),
                        icon: Icon(Icons.lock_outline_rounded, size: 19, color: onDark ? Colors.white70 : context.scheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 6),
                      FilledButton.icon(
                        onPressed: onChat,
                        icon: const Icon(Icons.auto_awesome, size: 17),
                        label: Text(tr('nav.talk')),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                          backgroundColor: AppTheme.coral,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ] else
                      Builder(
                        builder: (context) => IconButton(
                          tooltip: 'Menu',
                          onPressed: () => Scaffold.of(context).openEndDrawer(),
                          icon: Icon(Icons.menu_rounded, color: onDark ? Colors.white : context.scheme.onSurface),
                        ),
                      ),
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
      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 19, color: onDark ? Colors.white70 : context.scheme.onSurfaceVariant),
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
          foregroundColor: onDark ? Colors.white : context.scheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        ),
        child: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
      );
}

class _MobileMenu extends StatelessWidget {
  const _MobileMenu({required this.onJump, required this.onChat, required this.onCall});
  final void Function(String) onJump;
  final VoidCallback onChat;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    void go(String t) {
      Navigator.of(context).pop();
      Future<void>.delayed(const Duration(milliseconds: 140), () => onJump(t));
    }

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(8, 6, 8, 16), child: InstituteLogo(size: 34, onDark: context.isDark)),
            _tile(context, Icons.school_outlined, tr('nav.courses'), () => go('courses')),
            _tile(context, Icons.event_outlined, tr('nav.batches'), () => go('batches')),
            _tile(context, Icons.work_outline, tr('nav.placement'), () => go('placement')),
            _tile(context, Icons.help_outline, tr('nav.faq'), () => go('faq')),
            const Divider(height: 26),
            _tile(context, Icons.lock_outline, 'Staff sign in', () => go('desk')),
            _tile(context, Icons.science_outlined, 'Demo hub (judges)', () => go('demo')),
            _tile(
              context,
              context.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              context.isDark ? 'Light mode' : 'Dark mode',
              () => LeadDeskApp.themeMode.value = context.isDark ? ThemeMode.light : ThemeMode.dark,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: AppTheme.coral),
              onPressed: () {
                Navigator.of(context).pop();
                onChat();
              },
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(tr('hero.chat')),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: () {
                Navigator.of(context).pop();
                onCall();
              },
              icon: const Icon(Icons.call_outlined, size: 18),
              label: Text(tr('hero.call')),
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('${Institute.phone}\n${Institute.address}', style: context.texts.bodySmall?.copyWith(fontSize: 12.5, height: 1.6)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String label, VoidCallback onTap) => ListTile(
        leading: Icon(icon, size: 21),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.r12)),
        onTap: onTap,
      );
}

// -------------------------------------------------------------- chat launcher
class _ChatLauncher extends StatefulWidget {
  const _ChatLauncher({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_ChatLauncher> createState() => _ChatLauncherState();
}

class _ChatLauncherState extends State<_ChatLauncher> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: AppTheme.coral.withValues(alpha: 0.25 + 0.2 * _pulse.value),
              blurRadius: 16 + 12 * _pulse.value,
              spreadRadius: 1 + 2 * _pulse.value,
            ),
          ],
        ),
        child: child,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Ink(
            decoration: const BoxDecoration(gradient: AppTheme.coralGradient),
            padding: EdgeInsets.symmetric(horizontal: phone ? 16 : 20, vertical: phone ? 15 : 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Text(
                  phone ? 'Asha' : tr('nav.talk'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatDock extends StatelessWidget {
  const _ChatDock({super.key, required this.source, required this.onClose, this.prefill});
  final String source;
  final VoidCallback onClose;
  final String? prefill;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      width: 400,
      height: (h - 48).clamp(420.0, 680.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.r20),
        boxShadow: AppTheme.lift(context, y: 18, blur: 48, opacity: 0.22),
      ),
      clipBehavior: Clip.antiAlias,
      child: ProspectChatScreen(source: source, embedded: true, onClose: onClose, prefill: prefill),
    );
  }
}
