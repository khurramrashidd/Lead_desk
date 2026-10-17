import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../data/institute.dart';
import '../../l10n.dart';
import '../../main.dart';
import '../../services/repo.dart';
import '../../utils/responsive.dart';
import '../../widgets/brand.dart';
import '../../widgets/channel_links.dart';
import '../../widgets/lang_switch.dart';
import '../../widgets/site_widgets.dart';
import '../chat/prospect_chat_screen.dart';
import 'book_call_sheet.dart';
import 'sections.dart';

/// The pages of the public website. Home stays short; everything else lives behind ☰.
enum SitePage { home, courses, batches, placement, about, stories, faq, contact }

extension SitePageX on SitePage {
  String get label => switch (this) {
        SitePage.home => tr('nav.home'),
        SitePage.courses => tr('nav.courses'),
        SitePage.batches => tr('nav.batches'),
        SitePage.placement => tr('nav.placement'),
        SitePage.about => tr('nav.about'),
        SitePage.stories => tr('nav.stories'),
        SitePage.faq => tr('nav.faq'),
        SitePage.contact => tr('nav.contact'),
      };

  IconData get icon => switch (this) {
        SitePage.home => Icons.home_rounded,
        SitePage.courses => Icons.school_rounded,
        SitePage.batches => Icons.event_available_rounded,
        SitePage.placement => Icons.work_outline_rounded,
        SitePage.about => Icons.auto_awesome,
        SitePage.stories => Icons.reviews_outlined,
        SitePage.faq => Icons.quiz_outlined,
        SitePage.contact => Icons.qr_code_2,
      };
}

/// The SechTummit Trainers public website (and the Android app's home screen).
/// Asha, WhatsApp and Telegram are one tap away on every page.
class SiteScreen extends StatefulWidget {
  const SiteScreen({super.key, this.source = 'web', this.openChat = false});
  final String source;
  final bool openChat;

  @override
  State<SiteScreen> createState() => _SiteScreenState();
}

class _SiteScreenState extends State<SiteScreen> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _scroll = ScrollController();

  SitePage _page = SitePage.home;
  bool _chatOpen = false;
  String? _prefill;

  @override
  void initState() {
    super.initState();
    _chatOpen = widget.openChat;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _closeMenu() {
    if (_scaffold.currentState?.isEndDrawerOpen ?? false) _scaffold.currentState?.closeEndDrawer();
  }

  void _go(SitePage p) {
    _closeMenu();
    setState(() => _page = p);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _openChat([String? prefill]) {
    _closeMenu();
    if (screenSizeOf(context) == ScreenSize.phone) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProspectChatScreen(source: widget.source, prefill: prefill)));
    } else {
      setState(() {
        _prefill = prefill;
        _chatOpen = true;
      });
    }
  }

  void _openForm() => openChannel(context, ChatChannel.form);

  void _bookCall() => showBookCallSheet(context, source: widget.source);

  void _route(String r) {
    _closeMenu();
    Navigator.of(context).pushNamed(r);
  }

  List<Widget> _content(Kb kb) {
    final footer = SiteFooter(onNavigate: _route, onPage: _go);
    return switch (_page) {
      SitePage.home => [
          HomeHero(onChat: () => _openChat(), onCall: _bookCall),
          ScanToChatSection(onChat: () => _openChat()),
          HomeCourses(kb: kb, onAsk: _openChat, onAll: () => _go(SitePage.courses)),
          footer,
        ],
      SitePage.courses => [PageTitle(SitePage.courses.label), CoursesSection(kb: kb, onAsk: _openChat, onEnquire: _openForm, showHeader: false), footer],
      SitePage.batches => [PageTitle(SitePage.batches.label), BatchesSection(kb: kb, onBook: () => _openChat(tr('chat.s4')), showHeader: false), footer],
      SitePage.placement => [PageTitle(SitePage.placement.label), PlacementSection(kb: kb), footer],
      SitePage.about => [PageTitle(SitePage.about.label), AiSection(onChat: () => _openChat()), const WhyUsSection(), const StatsStrip(), footer],
      SitePage.stories => [PageTitle(SitePage.stories.label), const StoriesSection(), footer],
      SitePage.faq => [PageTitle(SitePage.faq.label), FaqSection(kb: kb, onChat: () => _openChat(), onCall: _bookCall, showHeader: false), footer],
      SitePage.contact => [PageTitle(SitePage.contact.label), ContactSection(onChat: () => _openChat(), onCall: _bookCall), footer],
    };
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
          return PopScope(
            // Back on a phone returns to Home before leaving the site.
            canPop: _page == SitePage.home,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _go(SitePage.home);
            },
            child: Scaffold(
              key: _scaffold,
              backgroundColor: context.scheme.surface,
              appBar: PreferredSize(
                preferredSize: Size.fromHeight(navHeight(context)),
                child: _TopBar(
                  page: _page,
                  onPage: _go,
                  onChat: () => _openChat(),
                  onMenu: () => _scaffold.currentState?.openEndDrawer(),
                ),
              ),
              endDrawer: _SiteMenu(
                page: _page,
                onPage: _go,
                onChat: () => _openChat(),
                onCall: () {
                  _closeMenu();
                  _bookCall();
                },
                onRoute: _route,
              ),
              body: Stack(
                children: [
                  Scrollbar(
                    controller: _scroll,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _content(kb)),
                    ),
                  ),
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
            ),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------ top bar
/// Always-visible bar (never overlaps the page, so it can always be tapped).
class _TopBar extends StatelessWidget {
  const _TopBar({required this.page, required this.onPage, required this.onChat, required this.onMenu});
  final SitePage page;
  final void Function(SitePage) onPage;
  final VoidCallback onChat;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final size = screenSizeOf(context);
    final phone = size == ScreenSize.phone;
    final dark = context.isDark;
    return Material(
      color: context.scheme.surface,
      child: Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.scheme.outlineVariant))),
        padding: SitePadding.of(context).copyWith(top: MediaQuery.paddingOf(context).top),
        height: navHeight(context) + MediaQuery.paddingOf(context).top,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Row(
              children: [
                InkWell(
                  onTap: () => onPage(SitePage.home),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                    child: InstituteLogo(size: phone ? 28 : 32, onDark: dark, compact: phone),
                  ),
                ),
                const Spacer(),
                if (size == ScreenSize.desktop) ...[
                  for (final p in [SitePage.courses, SitePage.placement, SitePage.faq])
                    _NavLink(p.label, () => onPage(p), active: page == p),
                  const SizedBox(width: 8),
                ],
                if (phone) const LangMenuButton() else const LangSwitch(),
                if (!phone) ...[
                  const SizedBox(width: 4),
                  const _ThemeToggle(),
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
                ],
                const SizedBox(width: 4),
                IconButton(
                  tooltip: tr('nav.menu'),
                  onPressed: onMenu,
                  iconSize: 26,
                  icon: Icon(Icons.menu_rounded, color: context.scheme.onSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return IconButton(
      tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
      onPressed: () => LeadDeskApp.themeMode.value = dark ? ThemeMode.light : ThemeMode.dark,
      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 20, color: context.scheme.onSurfaceVariant),
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink(this.label, this.onTap, {this.active = false});
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: active ? AppTheme.indigo : context.scheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        ),
        child: Text(label, style: TextStyle(fontSize: 14.5, fontWeight: active ? FontWeight.w800 : FontWeight.w600)),
      );
}

// --------------------------------------------------------------- ☰ menu
class _SiteMenu extends StatelessWidget {
  const _SiteMenu({required this.page, required this.onPage, required this.onChat, required this.onCall, required this.onRoute});
  final SitePage page;
  final void Function(SitePage) onPage;
  final VoidCallback onChat;
  final VoidCallback onCall;
  final void Function(String route) onRoute;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return Drawer(
      width: 320,
      backgroundColor: context.scheme.surface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            Row(children: [
              Padding(padding: const EdgeInsets.fromLTRB(8, 8, 0, 8), child: InstituteLogo(size: 32, onDark: dark)),
              const Spacer(),
              IconButton(tooltip: 'Close', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: 6),
            for (final p in SitePage.values)
              ListTile(
                leading: Icon(p.icon, size: 21, color: p == page ? AppTheme.indigo : null),
                title: Text(p.label, style: TextStyle(fontWeight: p == page ? FontWeight.w800 : FontWeight.w600, fontSize: 15)),
                selected: p == page,
                selectedTileColor: AppTheme.indigo.withValues(alpha: 0.08),
                selectedColor: AppTheme.indigo,
                dense: true,
                visualDensity: const VisualDensity(vertical: -1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.r12)),
                onTap: () => onPage(p),
              ),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: AppTheme.coral, foregroundColor: Colors.white),
                  onPressed: onChat,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: Text(tr('hero.chat')),
                ),
                const SizedBox(height: 8),
                Row(children: const [
                  Expanded(child: TalkButton(ChatChannel.whatsapp, compact: true)),
                  SizedBox(width: 8),
                  Expanded(child: TalkButton(ChatChannel.telegram, compact: true)),
                ]),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  onPressed: onCall,
                  icon: const Icon(Icons.support_agent_rounded, size: 18),
                  label: Text(tr('hero.call')),
                ),
              ]),
            ),
            const Divider(height: 28),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(children: [
                Text(tr('menu.language'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                const LangSwitch(),
              ]),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              secondary: Icon(dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined, size: 20),
              title: Text(tr('menu.dark'), style: const TextStyle(fontWeight: FontWeight.w700)),
              value: dark,
              onChanged: (v) => LeadDeskApp.themeMode.value = v ? ThemeMode.dark : ThemeMode.light,
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.lock_outline_rounded, size: 20),
              title: Text(tr('menu.staff'), style: const TextStyle(fontWeight: FontWeight.w600)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.r12)),
              onTap: () => onRoute('/desk'),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.science_outlined, size: 20),
              title: Text(tr('menu.judges'), style: const TextStyle(fontWeight: FontWeight.w600)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.r12)),
              onTap: () => onRoute('/demo'),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('${Institute.phone}\n${Institute.address}', style: context.texts.bodySmall?.copyWith(fontSize: 12, height: 1.6)),
            ),
          ],
        ),
      ),
    );
  }
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
              color: AppTheme.coral.withValues(alpha: 0.22 + 0.18 * _pulse.value),
              blurRadius: 14 + 10 * _pulse.value,
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
            padding: EdgeInsets.symmetric(horizontal: phone ? 16 : 20, vertical: phone ? 14 : 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 21),
                const SizedBox(width: 9),
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
      height: (h - 48 - navHeight(context)).clamp(420.0, 680.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.r20),
        boxShadow: AppTheme.lift(context, y: 18, blur: 48, opacity: 0.22),
      ),
      clipBehavior: Clip.antiAlias,
      child: ProspectChatScreen(source: source, embedded: true, onClose: onClose, prefill: prefill),
    );
  }
}
