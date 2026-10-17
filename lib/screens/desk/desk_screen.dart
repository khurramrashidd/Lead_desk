import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../main.dart';
import '../../services/auth_service.dart';
import '../../services/ops_service.dart';
import '../../services/repo.dart';
import '../../services/team_service.dart';
import '../../utils/ist.dart';
import '../../utils/responsive.dart';
import '../../widgets/brand.dart';
import '../../widgets/simulator.dart';
import '../auth/account_sheet.dart';
import '../auth/auth_gate.dart';
import 'activity_feed.dart';
import 'desk_kpis.dart';
import 'lead_detail.dart';
import 'lead_list.dart';
import 'reports_view.dart';

enum DeskView { leads, activity, reports }

/// The counsellor's workspace.
/// Desktop: sidebar + lead list + conversation + insights.
/// Tablet:  rail + list + detail.  Phone: one pane with bottom tabs.
class DeskScreen extends StatefulWidget {
  const DeskScreen({super.key});

  @override
  State<DeskScreen> createState() => _DeskScreenState();
}

class _DeskScreenState extends State<DeskScreen> {
  String? _selected;
  DeskView _view = DeskView.leads;

  String get _me => AuthService.displayName;

  void _open(String leadId) {
    final size = screenSizeOf(context);
    if (size == ScreenSize.phone) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (ctx) => Scaffold(
          body: SafeArea(
            child: LeadDetail(leadId: leadId, me: _me, onClose: () => Navigator.of(ctx).pop()),
          ),
        ),
      ));
      return;
    }
    setState(() {
      _selected = leadId;
      _view = DeskView.leads;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = screenSizeOf(context);
    if (size == ScreenSize.phone) return _phone(context);
    return _wide(context, size);
  }

  // ------------------------------------------------------------------ phone
  Widget _phone(BuildContext context) {
    return Scaffold(
      appBar: _topBar(context, compact: true),
      body: switch (_view) {
        DeskView.leads => Column(
            children: [
              const _AiHealthBanner(),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: const LiveKpiStrip(compact: true),
              ),
              Expanded(child: LeadList(selectedId: _selected, onSelect: _open)),
            ],
          ),
        DeskView.activity => ActivityFeed(onOpenLead: _open),
        DeskView.reports => const ReportsView(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _view.index,
        onDestinationSelected: (i) => setState(() => _view = DeskView.values[i]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.inbox_outlined), selectedIcon: Icon(Icons.inbox_rounded), label: 'Leads'),
          NavigationDestination(icon: Icon(Icons.bolt_outlined), selectedIcon: Icon(Icons.bolt_rounded), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'Reports'),
        ],
      ),
    );
  }

  // ------------------------------------------------------- tablet / desktop
  Widget _wide(BuildContext context, ScreenSize size) {
    final desktop = size == ScreenSize.desktop;
    final detail = _selected == null
        ? const _EmptyDetail()
        : LeadDetail(key: ValueKey(_selected), leadId: _selected!, me: _me);

    Widget content;
    switch (_view) {
      case DeskView.reports:
        content = const ReportsView();
      case DeskView.activity:
        content = Row(children: [
          SizedBox(width: 360, child: ActivityFeed(onOpenLead: _open)),
          const VerticalDivider(width: 1),
          Expanded(child: detail),
        ]);
      case DeskView.leads:
        content = Row(children: [
          SizedBox(
            width: desktop ? 372 : 330,
            child: Column(
              children: [
                if (desktop)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: const LiveKpiStrip(compact: true),
                  ),
                Expanded(child: LeadList(selectedId: _selected, onSelect: _open)),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: detail),
        ]);
    }

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            view: _view,
            onView: (v) => setState(() => _view = v),
            me: _me,
            expanded: desktop,
          ),
          Expanded(
            child: Column(
              children: [
                _topBar(context, compact: false),
                const Divider(height: 1),
                const _AiHealthBanner(),
                Expanded(child: content),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- top bar
  PreferredSizeWidget _topBar(BuildContext context, {required bool compact}) {
    final title = switch (_view) {
      DeskView.leads => 'Leads',
      DeskView.activity => 'Live activity',
      DeskView.reports => 'Reports',
    };
    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: compact ? 16 : 24,
      title: compact
          ? const LeadDeskLogo(size: 26)
          : Row(
              children: [
                Text(title, style: context.texts.titleLarge),
                const SizedBox(width: 12),
                if (_view == DeskView.leads) const _LiveBadge(),
              ],
            ),
      actions: [
        if (!compact) const Padding(padding: EdgeInsets.only(right: 4), child: Center(child: IstClock())),

        IconButton(
          tooltip: 'Simulate an enquiry (WhatsApp, Instagram, call, form…)',
          icon: const Icon(Icons.science_outlined),
          onPressed: () => showSimulator(context, onOpen: _open),
        ),
        _AlertsButton(onOpen: _open),
        const _TimeMachineButton(),
        if (StaffScope.isAdmin(context)) const _AdminButton(),
        if (!compact)
          IconButton(
          tooltip: context.isDark ? 'Light mode' : 'Dark mode',
          icon: Icon(context.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          onPressed: () => LeadDeskApp.themeMode.value = context.isDark ? ThemeMode.light : ThemeMode.dark,
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12, left: 4),
          child: _Avatar(onTap: () => showAccountSheet(context)),
        ),
      ],
    );
  }
}

/// Shown on the desk while Asha cannot reach any AI provider (wrong key, retired model, quota).
class _AiHealthBanner extends StatelessWidget {
  const _AiHealthBanner();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: OpsService.watchAiHealth(),
      builder: (context, snap) {
        final f = (snap.data?.data()?['lastFailure'] as Map?)?.cast<String, dynamic>();
        final at = Ist.fromTimestamp(f?['at']);
        if (f == null || at == null || DateTime.now().difference(at).inMinutes > 20) return const SizedBox.shrink();
        final errors = ((f['errors'] as List?) ?? const []).map((e) => '$e').toList();
        final first = errors.isEmpty ? '' : errors.first;
        return Material(
          color: AppTheme.warm.withValues(alpha: 0.14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: AppTheme.warm, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Asha could not reach the AI ${Ist.relative(at)}: people get instant knowledge-base answers and automatic retries. '
                  'Fix it in Admin → AI engine → Test.${first.isEmpty ? '' : '  ($first)'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              if (StaffScope.isAdmin(context))
                TextButton(onPressed: () => Navigator.of(context).pushNamed('/admin'), child: const Text('Open Admin')),
            ]),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ sidebar
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.view, required this.onView, required this.me, required this.expanded});
  final DeskView view;
  final ValueChanged<DeskView> onView;
  final String me;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final items = [
      (DeskView.leads, Icons.inbox_rounded, Icons.inbox_outlined, 'Leads'),
      (DeskView.activity, Icons.bolt_rounded, Icons.bolt_outlined, 'Activity'),
      (DeskView.reports, Icons.insights_rounded, Icons.insights_outlined, 'Reports'),
    ];

    return Container(
      width: expanded ? 232 : 76,
      decoration: BoxDecoration(
        color: context.scheme.surface,
        border: Border(right: BorderSide(color: context.scheme.outlineVariant)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(expanded ? 18 : 0, 20, 12, 22),
              child: expanded
                  ? const LeadDeskLogo(size: 30)
                  : const Center(child: BrandMark(size: 34)),
            ),
            for (final i in items)
              _SideItem(
                selected: view == i.$1,
                icon: view == i.$1 ? i.$2 : i.$3,
                label: i.$4,
                expanded: expanded,
                onTap: () => onView(i.$1),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Divider(color: context.scheme.outlineVariant),
            ),
            _SideItem(
              selected: false,
              icon: Icons.storefront_outlined,
              label: 'Walk-in',
              expanded: expanded,
              onTap: () => Navigator.of(context).pushNamed('/walkin'),
            ),
            _SideItem(
              selected: false,
              icon: Icons.public,
              label: 'Website',
              expanded: expanded,
              onTap: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false),
            ),
            const SizedBox(height: 10),
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                child: Row(children: [
                  _Avatar(onTap: () => showAccountSheet(context), radius: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(me,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.texts.titleSmall?.copyWith(fontSize: 13)),
                        Text(StaffScope.roleOf(context) ?? '',
                            style: context.texts.bodySmall?.copyWith(fontSize: 11)),
                      ],
                    ),
                  ),
                ]),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Center(child: _Avatar(onTap: () => showAccountSheet(context), radius: 16)),
              ),
          ],
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.selected,
    required this.icon,
    required this.label,
    required this.expanded,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final String label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppTheme.indigo : context.scheme.onSurfaceVariant;
    final body = Container(
      height: 44,
      margin: EdgeInsets.symmetric(horizontal: expanded ? 12 : 14, vertical: 3),
      padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0),
      decoration: BoxDecoration(
        color: selected ? AppTheme.indigo.withValues(alpha: 0.11) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.r12),
      ),
      child: Row(
        mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: fg),
          if (expanded) ...[
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: fg)),
          ],
        ],
      ),
    );
    return Tooltip(
      message: expanded ? '' : label,
      child: Material(color: Colors.transparent, child: InkWell(onTap: onTap, child: body)),
    );
  }
}

// ------------------------------------------------------------- top-bar bits
class _Avatar extends StatelessWidget {
  const _Avatar({required this.onTap, this.radius = 17});
  final VoidCallback onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final photo = AuthService.user?.photoURL;
    return Tooltip(
      message: AuthService.displayName,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: AppTheme.indigo.withValues(alpha: 0.15),
          backgroundImage: photo != null ? NetworkImage(photo) : null,
          child: photo == null
              ? Text(
                  AuthService.displayName.substring(0, 1).toUpperCase(),
                  style: TextStyle(color: AppTheme.indigo, fontWeight: FontWeight.w800, fontSize: radius * 0.85),
                )
              : null,
        ),
      ),
    );
  }
}

class _AdminButton extends StatelessWidget {
  const _AdminButton();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: TeamService.watchPending(),
      builder: (context, snap) {
        final waiting = snap.data?.docs.length ?? 0;
        return IconButton(
          tooltip: waiting == 0 ? 'Admin console' : 'Admin · $waiting request(s) waiting',
          onPressed: () => Navigator.pushNamed(context, '/admin'),
          icon: Badge(
            isLabelVisible: waiting > 0,
            label: Text('$waiting'),
            backgroundColor: AppTheme.hot,
            child: const Icon(Icons.admin_panel_settings_outlined),
          ),
        );
      },
    );
  }
}

class _TimeMachineButton extends StatelessWidget {
  const _TimeMachineButton();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Demo time machine',
      icon: const Icon(Icons.fast_forward_rounded),
      onSelected: (h) async {
        final messenger = ScaffoldMessenger.of(context);
        if (h == -1) {
          await Repo.jumpToTomorrowMorning();
        } else {
          await Repo.fastForward(hours: h);
        }
        messenger.showSnackBar(SnackBar(
          content: Text(h == 0
              ? 'Clock reset to real time.'
              : h == -1
                  ? '⏩ Now tomorrow 11 AM: due reminders and follow-ups are firing.'
                  : '⏩ Jumped $h hours ahead: reminders and follow-ups are firing now.'),
        ));
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: -1, child: ListTile(leading: Icon(Icons.wb_sunny_outlined), title: Text('Jump to tomorrow 11 AM'), dense: true)),
        PopupMenuItem(value: 24, child: ListTile(leading: Icon(Icons.fast_forward), title: Text('Fast-forward 1 day'), dense: true)),
        PopupMenuItem(value: 48, child: ListTile(leading: Icon(Icons.fast_forward), title: Text('Fast-forward 2 days'), dense: true)),
        PopupMenuItem(value: 0, child: ListTile(leading: Icon(Icons.restore), title: Text('Reset to real time'), dense: true)),
      ],
    );
  }
}

/// Hot-lead alerts for the signed-in counsellor (raised by the backend when a lead turns hot).
class _AlertsButton extends StatefulWidget {
  const _AlertsButton({required this.onOpen});
  final ValueChanged<String> onOpen;

  @override
  State<_AlertsButton> createState() => _AlertsButtonState();
}

class _AlertsButtonState extends State<_AlertsButton> {
  final _seen = <String>{};
  bool _primed = false;

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.user?.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: Repo.watchAlerts(uid),
      builder: (context, snap) {
        final all = snap.data ?? const [];
        final unread = all.where((a) => a.data()['read'] != true).toList();
        // Pop a snackbar for alerts that arrive while the desk is open.
        if (snap.hasData) {
          final fresh = unread.where((a) => !_seen.contains(a.id)).toList();
          _seen.addAll(all.map((a) => a.id));
          if (_primed && fresh.isNotEmpty) {
            final a = fresh.first;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('${a.data()['title'] ?? 'Hot lead'}'),
                action: SnackBarAction(label: 'Open', onPressed: () => widget.onOpen('${a.data()['leadId']}')),
              ));
            });
          }
          _primed = true;
        }
        return PopupMenuButton<String>(
          tooltip: 'Hot-lead alerts',
          icon: Badge(
            isLabelVisible: unread.isNotEmpty,
            label: Text('${unread.length}'),
            backgroundColor: AppTheme.hot,
            child: const Icon(Icons.notifications_none_rounded),
          ),
          onSelected: (id) {
            final a = all.firstWhere((x) => x.id == id);
            Repo.markAlertRead(id);
            widget.onOpen('${a.data()['leadId']}');
          },
          itemBuilder: (_) => all.isEmpty
              ? [const PopupMenuItem<String>(enabled: false, child: Text('No alerts yet. Hot leads assigned to you appear here.'))]
              : [
                  for (final a in all.take(12))
                    PopupMenuItem<String>(
                      value: a.id,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(a.data()['read'] == true ? Icons.done_rounded : Icons.local_fire_department_rounded,
                            color: a.data()['read'] == true ? null : AppTheme.hot),
                        title: Text('${a.data()['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${a.data()['body'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                ],
        );
      },
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.human.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppTheme.human, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          const Text('Live', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.human)),
        ]),
      );
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) => Container(
        color: context.scheme.surfaceContainerLow,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(opacity: 0.25, child: const BrandMark(size: 64)),
                const SizedBox(height: 20),
                Text('Pick a lead to open the conversation',
                    textAlign: TextAlign.center, style: context.texts.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Asha keeps every enquiry answered. You step in when it matters — one tap on "Take over".',
                  textAlign: TextAlign.center,
                  style: context.texts.bodyMedium?.copyWith(fontSize: 13.5),
                ),
              ],
            ),
          ),
        ),
      );
}
