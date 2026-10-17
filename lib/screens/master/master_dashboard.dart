import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_theme.dart';
import '../../services/auth_service.dart';
import '../../utils/ist.dart';
import '../../widgets/enrollment_card.dart';
import '../../widgets/lead_widgets.dart';
import '../auth/auth_gate.dart';
import '../desk/lead_detail.dart';

/// Master dashboard (admin): every person who ever enquired, one row per person.
///
/// Enquiries with the same phone number or email, at different times, on different channels
/// (WhatsApp, Telegram, website, Google Form, walk-in, call) and by different people (the
/// student, a parent, a friend) are put together under one banner. Charts on top, a table
/// below, and the full story + next actions when a row is opened.
class MasterDashboard extends StatefulWidget {
  const MasterDashboard({super.key});

  @override
  State<MasterDashboard> createState() => _MasterDashboardState();
}

enum _Filter { all, verify, hot, needsHuman, enrolled }

class _MasterDashboardState extends State<MasterDashboard> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  bool _hideSamples = true;

  final _stream = FirebaseFirestore.instance.collection('leads').orderBy('lastMessageAt', descending: true).limit(600).snapshots();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
      backgroundColor: context.scheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('Master dashboard'),
        bottom: const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(icon: Icon(Icons.groups_rounded, size: 18), text: 'People & enquiries'),
            Tab(icon: Icon(Icons.school_rounded, size: 18), text: 'Registered students'),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pushNamed('/desk'),
            icon: const Icon(Icons.dashboard_outlined, size: 17),
            label: const Text('Desk'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: TabBarView(children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Could not load: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final leads = snap.data!.docs
              .map((d) => (id: d.id, d: d.data()))
              .where((l) => l.d['mergedInto'] == null && l.d['burst'] != true && l.d['selftest'] != true && !(_hideSamples && l.d['seed'] == true))
              .toList();
          final people = Person.group(leads);
          final shown = _apply(people);
          final wide = MediaQuery.sizeOf(context).width > 980;
          return ListView(
            padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 12, vertical: 18),
            children: [
              _Kpis(people: people),
              const SizedBox(height: 16),
              Wrap(spacing: 16, runSpacing: 16, children: [
                _ChartCard(title: 'Enquiries per day (last 14 days)', width: wide ? 520 : double.infinity, child: _Daily(leads: leads)),
                _ChartCard(title: 'Funnel', width: wide ? 420 : double.infinity, child: _Bars(data: _funnel(people), color: AppTheme.indigo)),
                _ChartCard(title: 'Where people come from', width: wide ? 460 : double.infinity, child: _Bars(data: _bySource(people), color: AppTheme.info)),
                _ChartCard(title: 'Who is enquiring', width: wide ? 460 : double.infinity, child: _Bars(data: _byRelation(people), color: AppTheme.success)),
              ]),
              const SizedBox(height: 20),
              _toolbar(context, people.length, shown.length),
              const SizedBox(height: 10),
              _Table(people: shown, onOpen: (p) => _openPerson(context, p)),
            ],
          );
        },
      ),
        const _StudentsTab(),
      ]),
    ),
    );
  }

  Widget _toolbar(BuildContext context, int total, int shown) {
    final labels = {
      _Filter.all: 'All',
      _Filter.verify: '💳 Receipts to verify',
      _Filter.hot: '🔥 Hot',
      _Filter.needsHuman: '🙋 Needs a human',
      _Filter.enrolled: '🎓 Enrolled',
    };
    return Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
      SizedBox(
        width: 300,
        child: TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Name, phone, email, course…', isDense: true),
        ),
      ),
      for (final f in _Filter.values)
        ChoiceChip(label: Text(labels[f]!), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
      FilterChip(label: const Text('Hide sample data'), selected: _hideSamples, onSelected: (v) => setState(() => _hideSamples = v)),
      Text('$shown of $total people', style: context.texts.bodySmall),
      TextButton.icon(
        onPressed: () => _copyCsv(context),
        icon: const Icon(Icons.table_view_rounded, size: 17),
        label: const Text('Copy as CSV'),
      ),
    ]);
  }

  List<Person> _last = const [];

  List<Person> _apply(List<Person> people) {
    final q = _search.text.trim().toLowerCase();
    final digits = q.replaceAll(RegExp(r'\D'), '');
    final out = people.where((p) {
      final okFilter = switch (_filter) {
        _Filter.all => true,
        _Filter.verify => p.payment == 'receipt_received',
        _Filter.hot => p.temperature == 'hot',
        _Filter.needsHuman => p.needsHuman,
        _Filter.enrolled => p.stage == 'Enrolled',
      };
      if (!okFilter) return false;
      if (q.isEmpty) return true;
      return p.searchText.contains(q) || (digits.length >= 4 && p.phones.any((x) => x.contains(digits)));
    }).toList();
    _last = out;
    return out;
  }

  void _copyCsv(BuildContext context) {
    String c(Object? v) => '"${'${v ?? ''}'.replaceAll('"', '""')}"';
    final rows = [
      ['Name', 'Phones', 'Emails', 'Who enquired', 'Sources', 'Enquiries', 'Course', 'Score', 'Stage', 'Payment', 'First seen', 'Last activity'].map(c).join(','),
      for (final p in _last)
        [
          p.name,
          p.phones.join(' '),
          p.emails.join(' '),
          p.relations.join(' '),
          p.sources.join(' '),
          p.enquiries,
          p.course,
          p.score,
          p.stage,
          EnrollmentCard.statusLabel(p.payment),
          p.firstSeen == null ? '' : Ist.full(p.firstSeen!),
          p.lastSeen == null ? '' : Ist.full(p.lastSeen!),
        ].map(c).join(','),
    ];
    Clipboard.setData(ClipboardData(text: rows.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied ${_last.length} rows: paste into Excel or Google Sheets')));
  }

  void _openPerson(BuildContext context, Person p) {
    final role = StaffScope.roleOf(context) ?? '';
    showDialog<void>(
      context: context,
      builder: (d) => StaffScope(
        role: role,
        child: Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900, maxHeight: 820), child: _PersonView(person: p, role: role)),
        ),
      ),
    );
  }

  static Map<String, int> _funnel(List<Person> people) {
    int n(bool Function(Person) f) => people.where(f).length;
    return {
      'Enquired': people.length,
      'Engaged': n((p) => p.engaged),
      'Aptitude done': n((p) => p.aptitudeDone),
      'Demo / call booked': n((p) => p.booked),
      'Receipt sent': n((p) => p.payment == 'receipt_received' || p.payment == 'verified'),
      'Enrolled': n((p) => p.stage == 'Enrolled'),
    };
  }

  static Map<String, int> _bySource(List<Person> people) {
    final m = <String, int>{};
    for (final p in people) {
      for (final s in p.sources) {
        final k = sourceLabels[s] ?? s;
        m[k] = (m[k] ?? 0) + 1;
      }
    }
    return Map.fromEntries(m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }

  static Map<String, int> _byRelation(List<Person> people) {
    final m = <String, int>{};
    for (final p in people) {
      for (final r in p.relations) {
        m[r] = (m[r] ?? 0) + 1;
      }
    }
    return Map.fromEntries(m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }
}

// ------------------------------------------------------------------- model
/// One real person: every lead that shares a phone number or an email with another.
class Person {
  Person(this.leads);
  final List<({String id, Map<String, dynamic> d})> leads;

  static String _digits(Object? v) {
    final d = '${v ?? ''}'.replaceAll(RegExp(r'\D'), '');
    return d.length >= 10 ? d.substring(d.length - 10) : '';
  }

  static String _mail(Object? v) => '${v ?? ''}'.trim().toLowerCase();

  static Set<String> keysOf(Map<String, dynamic> d) {
    final keys = <String>{};
    void phone(Object? v) {
      final p = _digits(v);
      if (p.isNotEmpty) keys.add('p:$p');
    }

    void mail(Object? v) {
      final m = _mail(v);
      if (m.contains('@')) keys.add('e:$m');
    }

    phone(d['phone']);
    phone(d['studentPhone']);
    for (final x in (d['contactPhones'] as List?) ?? const []) {
      phone(x);
    }
    mail(d['email']);
    mail(d['studentEmail']);
    // Details typed into the enrolment form belong to the same person too.
    final form = ((d['enrollment'] as Map?)?['form'] as Map?) ?? const {};
    phone(form['phone']);
    phone(form['whatsapp']);
    mail(form['email']);
    for (final c in ((d['contacts'] as List?) ?? const []).whereType<Map>()) {
      phone(c['phone']);
      mail(c['email']);
    }
    return keys;
  }

  /// Union-find over shared phone numbers / emails.
  static List<Person> group(List<({String id, Map<String, dynamic> d})> leads) {
    final parent = List<int>.generate(leads.length, (i) => i);
    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    final owner = <String, int>{};
    for (var i = 0; i < leads.length; i++) {
      for (final k in keysOf(leads[i].d)) {
        final j = owner[k];
        if (j == null) {
          owner[k] = i;
        } else {
          parent[find(i)] = find(j);
        }
      }
    }
    final groups = <int, List<({String id, Map<String, dynamic> d})>>{};
    for (var i = 0; i < leads.length; i++) {
      groups.putIfAbsent(find(i), () => []).add(leads[i]);
    }
    final people = groups.values.map(Person.new).toList()
      ..sort((a, b) => (b.lastSeen ?? DateTime(2000)).compareTo(a.lastSeen ?? DateTime(2000)));
    return people;
  }

  Iterable<Map<String, dynamic>> get _ds => leads.map((l) => l.d);

  String get name {
    for (final d in _ds) {
      final s = '${d['studentName'] ?? ''}'.trim();
      if (s.isNotEmpty) return s;
    }
    for (final d in _ds) {
      final s = '${d['name'] ?? ''}'.trim();
      if (s.isNotEmpty) return s;
    }
    return 'Unknown visitor';
  }

  Set<String> get phones => {
        for (final d in _ds) ...[
          _digits(d['phone']),
          _digits(d['studentPhone']),
          for (final x in (d['contactPhones'] as List?) ?? const []) _digits(x),
        ],
      }..remove('');

  Set<String> get emails => {
        for (final d in _ds) ...[_mail(d['email']), _mail(d['studentEmail'])],
      }..removeWhere((e) => !e.contains('@'));

  Set<String> get sources => {
        for (final d in _ds) ...[
          ...((d['sources'] as List?) ?? const []).map((e) => '$e'),
          if (d['firstSource'] != null) '${d['firstSource']}',
        ],
      };

  /// Who enquired: student, parent, friend…
  List<({String name, String relation, String channel})> get contacts {
    final seen = <String>{};
    final out = <({String name, String relation, String channel})>[];
    for (final d in _ds) {
      for (final c in ((d['contacts'] as List?) ?? const []).whereType<Map>()) {
        final rel = '${c['relation'] ?? 'self'}';
        final nm = '${c['name'] ?? ''}'.trim();
        if (seen.add('$rel|${nm.toLowerCase()}')) out.add((name: nm, relation: rel, channel: '${c['channel'] ?? ''}'));
      }
    }
    return out;
  }

  static String _relation(String r) {
    if (r == 'self') return 'Student';
    if (r == 'parent' || r == 'guardian') return 'Parent';
    if (r == 'friend') return 'Friend';
    if (r == 'sibling') return 'Sibling';
    return 'Other';
  }

  Set<String> get relations => contacts.map((c) => _relation(c.relation)).toSet();

  int get enquiries => _ds.fold<int>(0, (s, d) => s + ((d['userMessages'] as num?)?.toInt() ?? 0));

  DateTime? get firstSeen => _ds.map((d) => Ist.fromTimestamp(d['createdAt'])).whereType<DateTime>().fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
  DateTime? get lastSeen => _ds.map((d) => Ist.fromTimestamp(d['lastMessageAt'])).whereType<DateTime>().fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

  Map<String, dynamic> get latest => leads.reduce((a, b) {
        final ta = Ist.fromTimestamp(a.d['lastMessageAt']) ?? DateTime(2000);
        final tb = Ist.fromTimestamp(b.d['lastMessageAt']) ?? DateTime(2000);
        return tb.isAfter(ta) ? b : a;
      }).d;

  String get course {
    for (final d in _ds) {
      if (d['enrolledCourseName'] != null) return '${d['enrolledCourseName']}';
    }
    for (final d in _ds) {
      final r = (d['recommendation'] as Map?)?['courseName'];
      if (r != null) return '$r';
    }
    for (final d in _ds) {
      final c = (d['enrollment'] as Map?)?['courseName'] ?? d['interestCourseId'];
      if (c != null) return '$c';
    }
    return '';
  }

  int get score => _ds.fold<int>(0, (s, d) => ((d['score'] as num?)?.toInt() ?? 0) > s ? (d['score'] as num).toInt() : s);
  String get temperature => _ds.any((d) => d['temperature'] == 'hot') ? 'hot' : _ds.any((d) => d['temperature'] == 'warm') ? 'warm' : 'cold';
  bool get needsHuman => _ds.any((d) => d['needsHuman'] == true);
  bool get engaged => _ds.any((d) => ((d['userMessages'] as num?) ?? 0) > 0 || (d['status'] != null && d['status'] != 'new'));
  bool get aptitudeDone => _ds.any((d) => (d['aptitude'] as Map?)?['status'] == 'done');
  bool get booked => _ds.any((d) => d['booking'] != null || (d['callback'] as Map?)?['startAt'] != null);

  /// The most important enrolment state across this person's enquiries.
  String get payment {
    const order = ['receipt_received', 'verified', 'awaiting_receipt', 'otp', 'confirm', 'form', 'awaiting_details', 'choosing_course', 'rejected', 'cancelled'];
    final all = _ds.map((d) => '${(d['enrollment'] as Map?)?['status'] ?? ''}').where((s) => s.isNotEmpty).toList();
    for (final s in order) {
      if (all.contains(s)) return s;
    }
    return '';
  }

  ({String id, Map<String, dynamic> d})? get enrollmentLead {
    for (final l in leads) {
      if (l.d['enrollment'] != null && '${(l.d['enrollment'] as Map)['status']}' == payment) return l;
    }
    return null;
  }

  String get stage {
    if (_ds.any((d) => d['status'] == 'admitted' || (d['enrollment'] as Map?)?['status'] == 'verified')) return 'Enrolled';
    if (payment == 'receipt_received') return 'Payment to verify';
    if (payment == 'awaiting_receipt') return 'Paying';
    if (booked) return 'Demo / call booked';
    if (_ds.any((d) => d['status'] == 'lost')) return 'Lost';
    if (engaged) return 'Engaged';
    return 'New';
  }

  String get searchText => [name, ...emails, ...phones, course, ...contacts.map((c) => c.name), ..._ds.map((d) => d['telegramUsername'] ?? '')].join(' ').toLowerCase();

  /// Every question asked, across all enquiries, newest first.
  List<({String text, String channel, DateTime? at})> get questions {
    final out = <({String text, String channel, DateTime? at})>[];
    for (final d in _ds) {
      for (final q in ((d['recentQuestions'] as List?) ?? const []).whereType<Map>()) {
        out.add((text: '${q['text'] ?? ''}', channel: '${q['channel'] ?? ''}', at: Ist.fromTimestamp(q['at'])));
      }
    }
    out.sort((a, b) => (b.at ?? DateTime(2000)).compareTo(a.at ?? DateTime(2000)));
    return out;
  }
}

// ------------------------------------------------------------------ widgets
class _Kpis extends StatelessWidget {
  const _Kpis({required this.people});
  final List<Person> people;

  @override
  Widget build(BuildContext context) {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final tiles = [
      ('People', '${people.length}', Icons.groups_rounded, AppTheme.indigo),
      ('New this week', '${people.where((p) => (p.firstSeen ?? DateTime(2000)).isAfter(weekAgo)).length}', Icons.fiber_new_rounded, AppTheme.info),
      ('Hot', '${people.where((p) => p.temperature == 'hot').length}', Icons.local_fire_department_rounded, AppTheme.hot),
      ('Demo / call booked', '${people.where((p) => p.booked).length}', Icons.event_available_rounded, AppTheme.human),
      ('Receipts to verify', '${people.where((p) => p.payment == 'receipt_received').length}', Icons.receipt_long_rounded, AppTheme.coral),
      ('Enrolled', '${people.where((p) => p.stage == 'Enrolled').length}', Icons.school_rounded, AppTheme.success),
    ];
    return Wrap(spacing: 12, runSpacing: 12, children: [
      for (final t in tiles)
        Container(
          width: 168,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.scheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.r16),
            border: Border.all(color: context.scheme.outlineVariant),
          ),
          child: Row(children: [
            Icon(t.$3, color: t.$4),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.$2, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                Text(t.$1, style: context.texts.bodySmall?.copyWith(fontSize: 11.5), overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child, required this.width});
  final String title;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.scheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.r16),
          border: Border.all(color: context.scheme.outlineVariant),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 12),
          child,
        ]),
      );
}

/// Horizontal bars with the value at the end.
class _Bars extends StatelessWidget {
  const _Bars({required this.data, required this.color});
  final Map<String, int> data;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return Text('No data yet', style: context.texts.bodySmall);
    final max = data.values.fold<int>(1, (a, b) => b > a ? b : a);
    return Column(children: [
      for (final e in data.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(width: 140, child: Text(e.key, style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 16,
                    width: (c.maxWidth * e.value / max).clamp(2.0, c.maxWidth).toDouble(),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
            ),
            SizedBox(width: 40, child: Text('${e.value}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
          ]),
        ),
    ]);
  }
}

/// New enquiries per day, last 14 days (IST).
class _Daily extends StatelessWidget {
  const _Daily({required this.leads});
  final List<({String id, Map<String, dynamic> d})> leads;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(14, (i) => DateTime(today.year, today.month, today.day).subtract(Duration(days: 13 - i)));
    final counts = List.filled(14, 0);
    for (final l in leads) {
      final at = Ist.fromTimestamp(l.d['createdAt']);
      if (at == null) continue;
      final day = DateTime(at.year, at.month, at.day);
      final i = days.indexWhere((d) => d == day);
      if (i >= 0) counts[i]++;
    }
    final max = counts.fold<int>(1, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 170,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < 14; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(counts[i] == 0 ? '' : '${counts[i]}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Container(
                  height: 120 * counts[i] / max + 2,
                  decoration: BoxDecoration(color: AppTheme.indigo.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(height: 4),
                Text('${days[i].day}', style: TextStyle(fontSize: 10, color: context.scheme.onSurfaceVariant)),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.people, required this.onOpen});
  final List<Person> people;
  final void Function(Person) onOpen;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('Nobody matches.', style: context.texts.bodyMedium)));
    }
    final rows = people.take(300).toList();
    return Container(
      decoration: BoxDecoration(
        color: context.scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.r16),
        border: Border.all(color: context.scheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          headingTextStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
          dataRowMinHeight: 52,
          dataRowMaxHeight: 72,
          columns: const [
            DataColumn(label: Text('Person')),
            DataColumn(label: Text('Contact')),
            DataColumn(label: Text('Who enquired')),
            DataColumn(label: Text('Channels')),
            DataColumn(label: Text('Msgs'), numeric: true),
            DataColumn(label: Text('Course')),
            DataColumn(label: Text('Score'), numeric: true),
            DataColumn(label: Text('Stage')),
            DataColumn(label: Text('Payment')),
            DataColumn(label: Text('Last activity')),
          ],
          rows: [
            for (final p in rows)
              DataRow(
                onSelectChanged: (_) => onOpen(p),
                color: WidgetStatePropertyAll(p.payment == 'receipt_received' ? AppTheme.hot.withValues(alpha: 0.06) : null),
                cells: [
                  DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (p.leads.length > 1) Text('${p.leads.length} enquiries merged', style: TextStyle(fontSize: 11, color: context.scheme.onSurfaceVariant)),
                  ])),
                  DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (p.phones.isNotEmpty) Text('+91 ${p.phones.first}', style: const TextStyle(fontSize: 12.5)),
                    if (p.emails.isNotEmpty) Text(p.emails.first, style: const TextStyle(fontSize: 12)),
                  ])),
                  DataCell(Text(p.relations.join(', '))),
                  DataCell(Text(p.sources.map((s) => sourceLabels[s] ?? s).join('  '), style: const TextStyle(fontSize: 12))),
                  DataCell(Text('${p.enquiries}')),
                  DataCell(SizedBox(width: 170, child: Text(p.course, overflow: TextOverflow.ellipsis))),
                  DataCell(Text('${p.score}${p.temperature == 'hot' ? ' 🔥' : ''}')),
                  DataCell(Text(p.stage)),
                  DataCell(p.payment.isEmpty
                      ? const Text('—')
                      : Text(EnrollmentCard.statusLabel(p.payment), style: TextStyle(color: EnrollmentCard.statusColor(p.payment), fontWeight: FontWeight.w700, fontSize: 12.5))),
                  DataCell(Text(p.lastSeen == null ? '' : Ist.full(p.lastSeen!), style: const TextStyle(fontSize: 12))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Everything about one person: who wrote, from where, what they asked, payment, actions.
class _PersonView extends StatelessWidget {
  const _PersonView({required this.person, required this.role});
  final Person person;
  final String role;

  static String _relLabel(String r) {
    switch (r) {
      case 'self':
        return '🎓 Student';
      case 'parent':
      case 'guardian':
        return '👨‍👩‍👧 Parent';
      case 'friend':
        return '🤝 Friend';
      case 'sibling':
        return '👫 Sibling';
      default:
        return '👤 $r';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = person;
    final phone = p.phones.isEmpty ? null : p.phones.first;
    final enrolLead = p.enrollmentLead;
    final latest = p.latest;
    final na = (latest['nextAction'] as Map?)?.cast<String, dynamic>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
        decoration: const BoxDecoration(gradient: AppTheme.brandGradient),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                [
                  ...p.phones.map((x) => '+91 $x'),
                  ...p.emails,
                  '${p.leads.length} enquir${p.leads.length == 1 ? 'y' : 'ies'}',
                  p.stage,
                ].join('  ·  '),
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ]),
          ),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (phone != null)
              FilledButton.icon(onPressed: () => launchUrl(Uri.parse('tel:+91$phone')), icon: const Icon(Icons.call_rounded, size: 17), label: const Text('Call')),
            if (phone != null)
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse('https://wa.me/91$phone'), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.chat_rounded, size: 17),
                label: const Text('WhatsApp'),
              ),
            for (final l in p.leads)
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (ctx) => StaffScope(
                    role: role,
                    child: Scaffold(body: SafeArea(child: LeadDetail(leadId: l.id, me: AuthService.displayName, onClose: () => Navigator.of(ctx).pop()))),
                  ),
                )),
                icon: const Icon(Icons.forum_outlined, size: 17),
                label: Text('Open ${sourceLabels['${l.d['firstSource'] ?? 'web'}'] ?? 'chat'} conversation'),
              ),
          ]),
          const SizedBox(height: 14),
          if (enrolLead != null) EnrollmentCard(leadId: enrolLead.id, enrollment: (enrolLead.d['enrollment'] as Map).cast<String, dynamic>()),
          InsightCard(
            title: 'Who enquired, and where',
            icon: Icons.groups_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final c in p.contacts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('${_relLabel(c.relation)}${c.name.isEmpty ? '' : ': ${c.name}'}'
                      '${c.channel.isEmpty ? '' : '  ·  ${sourceLabels[c.channel] ?? c.channel}'}'),
                ),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final s in p.sources) Chip(label: Text(sourceLabels[s] ?? s), visualDensity: VisualDensity.compact)]),
            ]),
          ),
          InsightCard(
            title: 'Timeline of enquiries',
            icon: Icons.timeline_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final l in [...p.leads]..sort((a, b) => (Ist.fromTimestamp(a.d['createdAt']) ?? DateTime(2000)).compareTo(Ist.fromTimestamp(b.d['createdAt']) ?? DateTime(2000))))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      '${Ist.fromTimestamp(l.d['createdAt']) == null ? '' : Ist.full(Ist.fromTimestamp(l.d['createdAt'])!)}  ·  ${sourceLabels['${l.d['firstSource'] ?? 'web'}'] ?? l.d['firstSource']}'
                      '  ·  ${l.d['name'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    for (final line in ((l.d['summary'] as List?) ?? const []).take(3))
                      Text('• $line', style: const TextStyle(fontSize: 12.5, height: 1.4)),
                  ]),
                ),
            ]),
          ),
          if (p.questions.isNotEmpty)
            InsightCard(
              title: 'Questions asked (all channels)',
              icon: Icons.help_outline_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final q in p.questions.take(12))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('“${q.text}”  ·  ${sourceLabels[q.channel] ?? q.channel}${q.at == null ? '' : '  ·  ${Ist.full(q.at!)}'}', style: const TextStyle(fontSize: 13)),
                  ),
              ]),
            ),
          InsightCard(
            title: 'Next action',
            icon: Icons.flag_rounded,
            child: Text(
              p.needsHuman
                  ? '🙋 ${latest['handoffReason'] ?? 'Needs a counsellor'}'
                  : na != null && na['done'] != true
                      ? '${playbookLabels[na['playbook']] ?? na['playbook'] ?? ''}: ${na['reason'] ?? ''}'
                      : 'Nothing pending.',
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
        ]),
      ),
    ]);
  }
}


/// Students whose payment was verified and course allotted, with their admission ID.
class _StudentsTab extends StatefulWidget {
  const _StudentsTab();

  @override
  State<_StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<_StudentsTab> {
  final _stream = FirebaseFirestore.instance.collection('students').orderBy('allottedAt', descending: true).limit(500).snapshots();
  final _search = TextEditingController();
  String _course = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static const _cols = [
    ('admissionId', 'Admission ID'),
    ('name', 'Name'),
    ('courseName', 'Course'),
    ('mode', 'Mode'),
    ('batch', 'Batch'),
    ('startMonth', 'Start'),
    ('phone', 'Mobile'),
    ('whatsapp', 'WhatsApp'),
    ('email', 'Email'),
    ('city', 'City'),
    ('qualification', 'Qualification'),
    ('dob', 'Date of birth'),
    ('guardianName', 'Parent / guardian'),
    ('guardianPhone', "Parent's mobile"),
    ('address', 'Address'),
    ('amount', 'Fee paid (₹)'),
    ('allottedBy', 'Allotted by'),
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Could not load: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = snap.data!.docs.map((d) => d.data()).toList();
        final courses = {for (final s in all) '${s['courseName'] ?? ''}'}..remove('');
        final q = _search.text.trim().toLowerCase();
        final rows = all.where((s) {
          if (_course.isNotEmpty && s['courseName'] != _course) return false;
          if (q.isEmpty) return true;
          return _cols.any((c) => '${s[c.$1] ?? ''}'.toLowerCase().contains(q));
        }).toList();
        return ListView(padding: const EdgeInsets.all(16), children: [
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 300,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Admission ID, name, phone…', isDense: true),
              ),
            ),
            ChoiceChip(label: const Text('All courses'), selected: _course.isEmpty, onSelected: (_) => setState(() => _course = '')),
            for (final c in courses) ChoiceChip(label: Text(c), selected: _course == c, onSelected: (_) => setState(() => _course = c)),
            Text('${rows.length} registered', style: context.texts.bodySmall),
            TextButton.icon(
              onPressed: () {
                String c(Object? v) => '"${'${v ?? ''}'.replaceAll('"', '""')}"';
                final csv = [
                  _cols.map((x) => c(x.$2)).join(','),
                  for (final s in rows) _cols.map((x) => c(s[x.$1])).join(','),
                ].join('\n');
                Clipboard.setData(ClipboardData(text: csv));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied ${rows.length} students: paste into Excel or Google Sheets')));
              },
              icon: const Icon(Icons.table_view_rounded, size: 17),
              label: const Text('Copy as CSV'),
            ),
          ]),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text('No registered students yet. They appear here when you verify a payment and allot a course.', style: context.texts.bodyMedium, textAlign: TextAlign.center)),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: context.scheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.r16),
                border: Border.all(color: context.scheme.outlineVariant),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingTextStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                  columns: [
                    for (final c in _cols) DataColumn(label: Text(c.$2)),
                    const DataColumn(label: Text('Allotted on')),
                  ],
                  rows: [
                    for (final s in rows)
                      DataRow(cells: [
                        for (final c in _cols)
                          DataCell(
                            c.$1 == 'address'
                                ? SizedBox(width: 220, child: Text('${s[c.$1] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis))
                                : Text('${s[c.$1] ?? ''}', style: TextStyle(fontWeight: c.$1 == 'admissionId' ? FontWeight.w800 : FontWeight.w400)),
                          ),
                        DataCell(Text(Ist.fromTimestamp(s['allottedAt']) == null ? '' : Ist.full(Ist.fromTimestamp(s['allottedAt'])!))),
                      ]),
                  ],
                ),
              ),
            ),
        ]);
      },
    );
  }
}
