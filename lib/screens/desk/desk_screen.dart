import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart';
import '../../services/repo.dart';
import '../../utils/ist.dart';
import '../../utils/responsive.dart';
import 'activity_feed.dart';
import 'lead_detail.dart';
import 'lead_list.dart';
import 'reports_view.dart';

/// The counsellor's live dashboard.
/// Phone: one pane + bottom tabs. Tablet: list + detail. Web/desktop: list + detail + live activity.
class DeskScreen extends StatefulWidget {
  const DeskScreen({super.key});

  @override
  State<DeskScreen> createState() => _DeskScreenState();
}

class _DeskScreenState extends State<DeskScreen> {
  static const counsellors = ['Priya', 'Amit', 'Sana'];
  String? _selected;
  int _tab = 0; // 0 leads, 1 activity, 2 reports
  String _me = counsellors.first;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final saved = p.getString('counsellor');
      if (saved != null && mounted) setState(() => _me = saved);
    });
  }

  Future<void> _setMe(String name) async {
    setState(() => _me = name);
    final p = await SharedPreferences.getInstance();
    await p.setString('counsellor', name);
  }

  void _open(String leadId) {
    final size = screenSizeOf(context);
    setState(() {
      _selected = leadId;
      _tab = 0;
    });
    if (size == ScreenSize.phone) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          body: SafeArea(child: LeadDetail(leadId: leadId, me: _me, onClose: () => Navigator.of(context).pop())),
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = screenSizeOf(context);
    final appBar = AppBar(
      title: const Text('Counsellor Desk'),
      actions: [
        if (size != ScreenSize.phone) const Center(child: IstClock()),
        if (size == ScreenSize.phone) const Center(child: IstClock(compact: true)),
        PopupMenuButton<int>(
          tooltip: 'Demo time machine',
          icon: const Icon(Icons.fast_forward),
          onSelected: (h) async {
            await Repo.fastForward(hours: h);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(h == 0 ? 'Clock reset to real time' : '⏩ Jumped $h hours ahead. Reminders and follow-ups are running…'),
            ));
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 24, child: Text('⏩ Fast-forward 1 day')),
            PopupMenuItem(value: 48, child: Text('⏩ Fast-forward 2 days')),
            PopupMenuItem(value: 0, child: Text('↺ Reset to real time')),
          ],
        ),
        PopupMenuButton<String>(
          tooltip: 'Who is using the desk',
          onSelected: _setMe,
          itemBuilder: (_) => [for (final c in counsellors) PopupMenuItem(value: c, child: Text(c))],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: size == ScreenSize.phone
                ? CircleAvatar(radius: 15, child: Text(_me[0]))
                : Chip(avatar: const Icon(Icons.person, size: 16), label: Text(_me)),
          ),
        ),
        IconButton(
          tooltip: 'Light / dark',
          icon: const Icon(Icons.brightness_6),
          onPressed: () => LeadDeskApp.themeMode.value =
              Theme.of(context).brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
        ),
      ],
    );

    final list = LeadList(selectedId: _selected, onSelect: _open);
    final detail = _selected == null
        ? const Center(child: Text('Select a lead'))
        : LeadDetail(key: ValueKey(_selected), leadId: _selected!, me: _me);

    Widget body;
    if (size == ScreenSize.phone) {
      body = [list, ActivityFeed(onOpenLead: _open), const ReportsView()][_tab];
      return Scaffold(
        appBar: appBar,
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.people_alt_outlined), label: 'Leads'),
            NavigationDestination(icon: Icon(Icons.bolt), label: 'Activity'),
            NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Reports'),
          ],
        ),
      );
    }

    final rail = NavigationRail(
      selectedIndex: _tab == 1 && size == ScreenSize.desktop ? 0 : _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      labelType: NavigationRailLabelType.all,
      destinations: const [
        NavigationRailDestination(icon: Icon(Icons.people_alt_outlined), label: Text('Leads')),
        NavigationRailDestination(icon: Icon(Icons.bolt), label: Text('Activity')),
        NavigationRailDestination(icon: Icon(Icons.bar_chart), label: Text('Reports')),
      ],
    );

    if (_tab == 2) {
      body = const ReportsView();
    } else if (_tab == 1 && size == ScreenSize.tablet) {
      body = Row(children: [
        SizedBox(width: 340, child: ActivityFeed(onOpenLead: _open)),
        const VerticalDivider(width: 1),
        Expanded(child: detail),
      ]);
    } else {
      body = Row(children: [
        SizedBox(width: 340, child: list),
        const VerticalDivider(width: 1),
        Expanded(child: detail),
        if (size == ScreenSize.desktop) ...[
          const VerticalDivider(width: 1),
          SizedBox(width: 320, child: ActivityFeed(onOpenLead: _open)),
        ],
      ]);
    }

    return Scaffold(
      appBar: appBar,
      body: Row(children: [rail, const VerticalDivider(width: 1), Expanded(child: body)]),
    );
  }
}
