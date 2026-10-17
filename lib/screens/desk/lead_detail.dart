import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_theme.dart';
import '../../services/repo.dart';
import '../../services/team_service.dart';
import '../../utils/ist.dart';
import '../../widgets/enrollment_card.dart';
import '../../widgets/lead_widgets.dart';
import '../../widgets/message_bubble.dart';

/// Everything about one lead: the live conversation, what the AI and the rules worked out,
/// and the one tap that puts a human in charge.
class LeadDetail extends StatelessWidget {
  const LeadDetail({super.key, required this.leadId, required this.me, this.onClose});
  final String leadId;
  final String me;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: Repo.watchLead(leadId),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Could not load this lead: ${snap.error}'));
        final d = snap.data?.data();
        if (d == null) return const Center(child: CircularProgressIndicator());
        if (d['mergedInto'] != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                'This enquiry turned out to be the same person as another lead, so the two timelines were merged.',
                textAlign: TextAlign.center,
                style: context.texts.bodyMedium,
              ),
            ),
          );
        }

        return LayoutBuilder(builder: (context, c) {
          final header = _Header(leadId: leadId, d: d, me: me, onClose: onClose);
          final chat = _Conversation(key: ValueKey('conv_$leadId'), leadId: leadId, d: d, me: me);
          final insights = _Insights(leadId: leadId, d: d, me: me);

          if (c.maxWidth >= 920) {
            return Container(
              color: context.scheme.surfaceContainerLow,
              child: Column(children: [
                header,
                const Divider(height: 1),
                Expanded(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(flex: 6, child: chat),
                    const VerticalDivider(width: 1),
                    SizedBox(width: 372, child: insights),
                  ]),
                ),
              ]),
            );
          }
          return DefaultTabController(
            length: 2,
            child: Container(
              color: context.scheme.surfaceContainerLow,
              child: Column(children: [
                header,
                Material(
                  color: context.scheme.surface,
                  child: const TabBar(tabs: [
                    Tab(height: 44, child: Text('Conversation')),
                    Tab(height: 44, child: Text('AI insights')),
                  ]),
                ),
                Expanded(child: TabBarView(children: [chat, insights])),
              ]),
            ),
          );
        });
      },
    );
  }
}

// ----------------------------------------------------------------- header
class _Header extends StatelessWidget {
  const _Header({required this.leadId, required this.d, required this.me, this.onClose});
  final String leadId;
  final Map<String, dynamic> d;
  final String me;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final name = (d['name'] as String?)?.trim().isNotEmpty == true ? d['name'] as String : 'New enquiry';
    final latin = d['nameLatin'] as String?;
    final aliases = (d['aliases'] as List?)?.cast<String>() ?? const <String>[];
    final phone = d['phone'] as String?;
    final paused = d['aiPaused'] == true;
    final status = d['status'] as String? ?? 'new';
    final temp = d['temperature'] as String?;
    final lang = [d['language'], d['register']].where((e) => e != null && '$e'.isNotEmpty).join(' · ');
    final assigned = d['assignedTo'] as String?;

    final takeover = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: paused ? AppTheme.ai : AppTheme.human,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      ),
      icon: Icon(paused ? Icons.smart_toy_rounded : Icons.headset_mic_rounded, size: 18),
      label: Text(paused ? 'Hand back to Asha' : 'Take over'),
      onPressed: () => Repo.setTakeover(leadId, !paused, me),
    );

    final callBtn = (phone != null && phone.isNotEmpty)
        ? IconButton.filledTonal(
            tooltip: 'Call +91 $phone',
            onPressed: () => launchUrl(Uri.parse('tel:+91$phone')),
            icon: const Icon(Icons.call_rounded, size: 19),
          )
        : null;

    final statusMenu = PopupMenuButton<String>(
      tooltip: 'Change status',
      initialValue: status,
      onSelected: (s) => Repo.setStatus(leadId, s),
      itemBuilder: (_) => [for (final e in statusLabels.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
      child: StatusPill(status),
    );

    final identity = Row(
      children: [
        if (onClose != null) IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: onClose),
        CircleAvatar(
          radius: 22,
          backgroundColor: AppTheme.temperature(temp).withValues(alpha: 0.14),
          child: Text(
            initialsOf(latin?.isNotEmpty == true ? latin : name),
            style: TextStyle(color: AppTheme.temperature(temp), fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                latin != null && latin.isNotEmpty && latin != name ? '$name · $latin' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.titleLarge?.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (phone != null && phone.isNotEmpty) '+91 $phone',
                  if ((d['city'] as String?)?.isNotEmpty == true) '📍 ${d['city']}',
                  if (lang.isNotEmpty) '🗣 $lang',
                  if (assigned != null && assigned.isNotEmpty) '👤 $assigned',
                  if (aliases.isNotEmpty) '🔗 also “${aliases.join('”, “')}”',
                ].join('   ·   '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );

    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 620) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            identity,
            const SizedBox(height: 10),
            Row(children: [statusMenu, const Spacer(), if (callBtn != null) ...[callBtn, const SizedBox(width: 8)], takeover]),
          ]);
        }
        return Row(children: [
          Expanded(child: identity),
          statusMenu,
          const SizedBox(width: 10),
          if (callBtn != null) ...[callBtn, const SizedBox(width: 8)],
          takeover,
        ]);
      }),
    );
  }
}

// ----------------------------------------------------------- conversation
class _Conversation extends StatefulWidget {
  const _Conversation({super.key, required this.leadId, required this.d, required this.me});
  final String leadId;
  final Map<String, dynamic> d;
  final String me;

  @override
  State<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends State<_Conversation> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _messages = Repo.watchMessages(widget.leadId);
  int _lastCount = 0;

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    _text.clear();
    await Repo.sendCounsellorMessage(widget.leadId, body, channel: Repo.replyChannel(widget.d), me: widget.me);
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paused = widget.d['aiPaused'] == true;
    final channel = Repo.replyChannel(widget.d);
    return Column(children: [
      Expanded(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _messages,
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            if (docs.length != _lastCount) {
              _lastCount = docs.length;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
              });
            }
            if (docs.isEmpty) return Center(child: Text('No messages yet', style: context.texts.bodyMedium));
            return ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              itemCount: docs.length,
              itemBuilder: (context, i) => MessageBubble.fromDoc(docs[i].data()),
            );
          },
        ),
      ),
      if (paused)
        Container(
          color: context.scheme.surface,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: SafeArea(
            top: false,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(hintText: 'Reply as ${widget.me} · goes out on ${sourceLabels[channel] ?? channel}'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _send,
                icon: const Icon(Icons.send_rounded),
                style: IconButton.styleFrom(padding: const EdgeInsets.all(14), backgroundColor: AppTheme.human),
              ),
            ]),
          ),
        )
      else
        Container(
          width: double.infinity,
          color: AppTheme.ai.withValues(alpha: 0.07),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            const Icon(Icons.smart_toy_rounded, size: 17, color: AppTheme.ai),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Asha is handling this conversation. Tap “Take over” and she stops instantly.',
                style: context.texts.bodySmall?.copyWith(fontSize: 12.5),
              ),
            ),
          ]),
        ),
    ]);
  }
}

// --------------------------------------------------------------- insights
class _Insights extends StatelessWidget {
  const _Insights({required this.leadId, required this.d, required this.me});
  final String leadId;
  final Map<String, dynamic> d;
  final String me;

  Map<String, dynamic>? _map(String k) => (d[k] as Map?)?.cast<String, dynamic>();

  @override
  Widget build(BuildContext context) {
    final summary = (d['summary'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    final objections = (d['objections'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    final suggested = d['suggestedMessage'] as String?;
    final na = _map('nextAction');
    final rec = _map('recommendation');
    final apt = _map('aptitude');
    final booking = _map('booking');
    final callback = _map('callback');
    final callTask = _map('callTask');
    final breakdown = _map('scoreBreakdown');
    final profile = _map('profile') ?? const <String, dynamic>{};
    final contacts = ((d['contacts'] as List?) ?? const []).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
    final channel = Repo.replyChannel(d);
    final guardBlocks = (d['guardBlocks'] as num?)?.toInt() ?? 0;
    final dupOf = d['possibleDuplicateOf'] as String?;

    return Container(
      color: context.scheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          if (dupOf != null) _DuplicateCard(leadId: leadId, otherId: dupOf, reason: '${d['possibleDuplicateReason'] ?? ''}'),
          if ((d['relatedLeads'] as Map?)?.isNotEmpty == true)
            _LinkedCard(leadId: leadId, me: me, related: (d['relatedLeads'] as Map).cast<String, dynamic>()),
          if ((_map('ai')?['lastError'] as String?)?.isNotEmpty == true) _AiTroubleCard(ai: _map('ai')!),
          if (_map('deliveryIssue') != null) _DeliveryCard(issue: _map('deliveryIssue')!),
          if (_map('onboarding') != null) _IntakeCard(ob: _map('onboarding')!, d: d),
          if ((d['recentQuestions'] as List?)?.isNotEmpty == true) _QuestionsCard(questions: (d['recentQuestions'] as List).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList()),
          _HistoryCard(leadId: leadId, d: d, me: me),
          if (d['needsHuman'] == true)
            InsightCard(
              title: 'Needs a human',
              icon: Icons.pan_tool_rounded,
              accent: AppTheme.hot,
              child: Text(
                (d['handoffReason'] as String?)?.isNotEmpty == true ? d['handoffReason'] as String : 'Asha asked for help on this one.',
                style: context.texts.bodyMedium?.copyWith(fontSize: 13),
              ),
            ),
          if (_map('enrollment') != null) EnrollmentCard(leadId: leadId, enrollment: _map('enrollment')!),
          if (callback != null) _CallbackCard(leadId: leadId, callback: callback, phone: d['phone'] as String?),
          if (callTask != null) _CallTaskCard(leadId: leadId, task: callTask, phone: d['phone'] as String?, me: me),

          // ---- score with its breakdown
          InsightCard(
            title: 'Lead score',
            icon: Icons.speed_rounded,
            trailing: Text('rules + AI', style: TextStyle(fontSize: 10.5, color: context.scheme.onSurfaceVariant)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                ScoreBadge(score: (d['score'] as num?)?.toInt() ?? 0, temperature: d['temperature'] as String?, big: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    TempChip(d['temperature'] as String?),
                    for (final s in (d['sources'] as List?)?.map((e) => '$e') ?? const <String>[]) SmallChip(sourceLabels[s] ?? s),
                    if (guardBlocks > 0) SmallChip('🛡 $guardBlocks blocked', color: AppTheme.guard),
                  ]),
                ),
              ]),
              if (breakdown != null) ...[
                const SizedBox(height: 14),
                _Bar('Fit', breakdown['fit'], 20, AppTheme.indigo),
                _Bar('Intent', breakdown['intent'], 25, AppTheme.coral),
                _Bar('Engagement', breakdown['engagement'], 15, AppTheme.info),
                _Bar('Recency', breakdown['recency'], 15, AppTheme.human),
                _Bar('Aptitude', breakdown['aptitude'], 10, AppTheme.ai),
                _Bar('AI read', breakdown['aiRead'], 15, AppTheme.cold),
                if (((breakdown['objections'] as num?) ?? 0) < 0) _Bar('Worries', breakdown['objections'], -12, AppTheme.hot),
                const SizedBox(height: 6),
                for (final r in ((breakdown['reasons'] as List?) ?? const []).take(6))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('• $r', style: TextStyle(fontSize: 11.5, height: 1.4, color: context.scheme.onSurfaceVariant)),
                  ),
              ],
            ]),
          ),

          InsightCard(
            title: 'Three-line summary',
            icon: Icons.notes_rounded,
            child: summary.isEmpty
                ? Text('Appears after Asha\'s first reply.', style: context.texts.bodyMedium?.copyWith(fontSize: 13))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < summary.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              width: 18,
                              height: 18,
                              margin: const EdgeInsets.only(right: 8, top: 1),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: AppTheme.indigo.withValues(alpha: 0.12), shape: BoxShape.circle),
                              child: Text('${i + 1}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppTheme.indigo)),
                            ),
                            Expanded(child: Text(summary[i], style: const TextStyle(fontSize: 13.2, height: 1.45))),
                          ]),
                        ),
                    ],
                  ),
          ),

          InsightCard(
            title: 'Objections detected',
            icon: Icons.block_rounded,
            child: objections.isEmpty
                ? Text('None raised yet.', style: context.texts.bodyMedium?.copyWith(fontSize: 13))
                : Wrap(spacing: 6, runSpacing: 6, children: [for (final o in objections) SmallChip(objectionLabels[o] ?? o, color: AppTheme.warm)]),
          ),

          if (suggested != null && suggested.trim().isNotEmpty)
            InsightCard(
              title: 'Suggested next message',
              icon: Icons.auto_awesome_rounded,
              accent: AppTheme.indigo,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppTheme.indigo.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(AppTheme.r12)),
                  child: SelectableText(suggested, style: const TextStyle(fontSize: 13.2, height: 1.5)),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: Text('Send as $me', overflow: TextOverflow.ellipsis),
                      onPressed: () => Repo.sendCounsellorMessage(leadId, suggested, channel: channel, me: me),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Copy',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () => Clipboard.setData(ClipboardData(text: suggested)),
                  ),
                ]),
              ]),
            ),

          if (na != null)
            InsightCard(
              title: 'Next best action',
              icon: Icons.bolt_rounded,
              accent: na['done'] == true ? null : AppTheme.info,
              trailing: na['playbook'] == null ? null : SmallChip(playbookLabels[na['playbook']] ?? '${na['playbook']}', color: AppTheme.info),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(_channelIcon(na['channel'] as String?), style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      na['done'] == true ? 'Done' : '${sourceLabels[na['channel']] ?? na['channel']} · ${Ist.full(Ist.fromTimestamp(na['at']) ?? DateTime.now())}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                  if (na['done'] != true) Text(Ist.relative(Ist.fromTimestamp(na['at'])), style: context.texts.bodySmall?.copyWith(fontSize: 11.5)),
                ]),
                if ((na['reason'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text('Why: ${na['reason']}', style: context.texts.bodySmall?.copyWith(fontSize: 12.5, height: 1.45)),
                ],
                if ((na['message'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text('“${na['message']}”', style: const TextStyle(fontSize: 13, height: 1.45)),
                ],
                if (na['done'] != true && (na['message'] as String?)?.isNotEmpty == true && na['channel'] != 'call')
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        await Repo.sendCounsellorMessage(leadId, na['message'] as String, channel: channel, me: me);
                        await Repo.leads.doc(leadId).set({
                          'nextAction': {'done': true},
                        }, SetOptions(merge: true));
                      },
                      child: const Text('Send it now'),
                    ),
                  ),
              ]),
            ),

          if (rec != null)
            InsightCard(
              title: 'Recommended program',
              icon: Icons.school_rounded,
              accent: AppTheme.ai,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${rec['courseName'] ?? rec['courseId']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 5),
                Text('${rec['reason'] ?? ''}', style: const TextStyle(fontSize: 13, height: 1.45)),
              ]),
            ),

          if (apt != null && apt['status'] != 'not_started') _AptitudeCard(apt: apt),

          if (booking != null)
            InsightCard(
              title: 'Demo class',
              icon: Icons.event_available_rounded,
              accent: AppTheme.human,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${booking['title']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 3),
                Text(Ist.full(Ist.fromTimestamp(booking['startAt']) ?? DateTime.now()), style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  _TestRemindersButton(leadId: leadId),
                  _ReminderDot(done: booking['reminded24'] == true, label: '24 h reminder'),
                  _ReminderDot(done: booking['reminded1'] == true, label: '1 h reminder'),
                  _ReminderDot(
                    done: booking['calendarSync'] == 'ok',
                    label: booking['calendarSync'] == 'ok' ? 'In Google Calendar' : 'Calendar sync off',
                  ),
                ]),
                Wrap(spacing: 4, children: [
                  if (booking['calendarEventLink'] != null)
                    TextButton.icon(
                      icon: const Icon(Icons.calendar_month_rounded, size: 15),
                      label: const Text('Open event'),
                      onPressed: () => launchUrl(Uri.parse(booking['calendarEventLink'] as String), mode: LaunchMode.externalApplication),
                    ),
                  if (booking['calendarUrl'] != null)
                    TextButton.icon(
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: const Text('Student\'s calendar link'),
                      onPressed: () => launchUrl(Uri.parse(booking['calendarUrl'] as String), mode: LaunchMode.externalApplication),
                    ),
                ]),
              ]),
            )
          else
            _BookCard(leadId: leadId),

          _AssignCard(leadId: leadId, assignedUid: d['assignedUid'] as String?, assignedTo: d['assignedTo'] as String?, lang: d['assignedLang'] as String?),

          if (contacts.length > 1 || (contacts.isNotEmpty && contacts.first['relation'] != 'self') || (d['studentName'] as String?)?.isNotEmpty == true)
            InsightCard(
              title: 'People on this admission',
              icon: Icons.groups_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if ((d['studentName'] as String?)?.isNotEmpty == true)
                  Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('🎓 Student: ${d['studentName']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                for (final c in contacts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${relationLabels[c['relation']] ?? c['relation'] ?? 'Contact'}: ${c['name'] ?? ''}${(c['phone'] as String?)?.isNotEmpty == true ? ' · ${c['phone']}' : ''} · ${sourceLabels[c['channel']] ?? c['channel'] ?? ''}',
                      style: const TextStyle(fontSize: 12.8),
                    ),
                  ),
              ]),
            ),

          if (profile.isNotEmpty)
            InsightCard(
              title: 'What we know',
              icon: Icons.person_outline_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in profile.entries)
                    if ('${e.value}'.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(fontSize: 13, height: 1.45, fontFamily: 'Jakarta', color: context.scheme.onSurface),
                            children: [
                              TextSpan(text: '${_pretty(e.key)}: ', style: TextStyle(fontWeight: FontWeight.w700, color: context.scheme.onSurface)),
                              TextSpan(text: '${e.value}', style: TextStyle(color: context.scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),

          _LogTouchCard(leadId: leadId, me: me),
        ],
      ),
    );
  }

  static String _pretty(String key) {
    final spaced = key.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]!.toLowerCase()}');
    return spaced.isEmpty ? key : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }

  static String _channelIcon(String? c) => switch (c) {
        'whatsapp' => '🟢',
        'telegram' => '✈️',
        'instagram' => '📸',
        'call' => '📞',
        _ => '🌐',
      };
}

class _Bar extends StatelessWidget {
  const _Bar(this.label, this.value, this.max, this.color);
  final String label;
  final Object? value;
  final num max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final v = (value as num?) ?? 0;
    final frac = max == 0 ? 0.0 : (v / max).clamp(0, 1).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(children: [
        SizedBox(width: 78, child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: frac, minHeight: 7, color: color, backgroundColor: color.withValues(alpha: 0.12)),
          ),
        ),
        SizedBox(width: 44, child: Text('${v > 0 ? '+' : ''}$v', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

class _AptitudeCard extends StatelessWidget {
  const _AptitudeCard({required this.apt});
  final Map<String, dynamic> apt;

  @override
  Widget build(BuildContext context) {
    final answers = ((apt['answers'] as List?) ?? const []).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
    const levels = ['', 'easy', 'medium', 'hard'];
    return InsightCard(
      title: 'Aptitude check',
      icon: Icons.psychology_rounded,
      accent: AppTheme.ai,
      trailing: Text('scored on server', style: TextStyle(fontSize: 10.5, color: context.scheme.onSurfaceVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          SmallChip('${apt['status']}'.replaceAll('_', ' ')),
          SmallChip('${apt['correct'] ?? 0}/${answers.isEmpty ? (apt['status'] == 'done' ? 4 : 0) : answers.length} correct'),
          if (apt['points'] != null) SmallChip('${apt['points']}/11 points'),
          if (apt['band'] != null) SmallChip('${apt['band']}', color: AppTheme.ai),
        ]),
        if (answers.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final a in answers)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (a['correct'] == true ? AppTheme.success : AppTheme.hot).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${a['correct'] == true ? '✓' : '✗'} ${a['id']} · ${levels[((a['level'] as num?)?.toInt() ?? 2).clamp(1, 3).toInt()]} · picked ${a['picked']}',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
          ]),
        ],
        if ((apt['result'] as String?)?.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Text('${apt['result']}', style: const TextStyle(fontSize: 13, height: 1.45)),
        ],
      ]),
    );
  }
}

class _DuplicateCard extends StatelessWidget {
  const _DuplicateCard({required this.leadId, required this.otherId, required this.reason});
  final String leadId;
  final String otherId;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return InsightCard(
      title: 'Possible duplicate',
      icon: Icons.call_merge_rounded,
      accent: AppTheme.warm,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: Repo.watchLead(otherId),
        builder: (context, snap) {
          final o = snap.data?.data() ?? const <String, dynamic>{};
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(reason, style: context.texts.bodyMedium?.copyWith(fontSize: 13)),
            const SizedBox(height: 6),
            Text('Other lead: ${o['name'] ?? otherId}${o['phone'] != null ? ' · ${o['phone']}' : ''} · ${(o['sources'] as List?)?.join(', ') ?? ''}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                icon: const Icon(Icons.call_merge_rounded, size: 16),
                label: const Text('Same person: merge'),
                onPressed: () => _run(context, () => Repo.merge(otherId, leadId), 'Merged into one timeline'),
              ),
              OutlinedButton(
                onPressed: () => _run(context, () => Repo.dismissDuplicate(leadId, otherId), 'Kept as two people'),
                child: const Text('Different people'),
              ),
            ]),
          ]);
        },
      ),
    );
  }
}

/// Same family / shared phone, different students: separate admissions, linked both ways.
class _LinkedCard extends StatelessWidget {
  const _LinkedCard({required this.leadId, required this.me, required this.related});
  final String leadId;
  final String me;
  final Map<String, dynamic> related;

  @override
  Widget build(BuildContext context) {
    return InsightCard(
      title: 'Linked enquiries',
      icon: Icons.family_restroom_rounded,
      accent: AppTheme.info,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Same phone or email, but a different student, so they stay separate admissions.',
            style: context.texts.bodySmall?.copyWith(fontSize: 12)),
        const SizedBox(height: 8),
        for (final e in related.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${(e.value as Map?)?['name'] ?? e.key}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  Text('${(e.value as Map?)?['reason'] ?? ''}', style: context.texts.bodySmall?.copyWith(fontSize: 11.5)),
                ]),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (ctx) => Scaffold(
                    body: SafeArea(child: LeadDetail(leadId: e.key, me: me, onClose: () => Navigator.of(ctx).pop())),
                  ),
                )),
                child: const Text('Open'),
              ),
              IconButton(
                tooltip: 'Actually the same student: merge',
                icon: const Icon(Icons.call_merge_rounded, size: 18),
                onPressed: () => _run(context, () => Repo.merge(leadId, e.key), 'Merged into one timeline'),
              ),
            ]),
          ),
      ]),
    );
  }
}

Future<void> _run(BuildContext context, Future<void> Function() job, String ok) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await job();
    messenger.showSnackBar(SnackBar(content: Text('✅ $ok')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('❌ $e')));
  }
}

/// Sends the 24-hour and 1-hour reminders right now, so a booking can be tested without waiting.
class _TestRemindersButton extends StatefulWidget {
  const _TestRemindersButton({required this.leadId});
  final String leadId;

  @override
  State<_TestRemindersButton> createState() => _TestRemindersButtonState();
}

class _TestRemindersButtonState extends State<_TestRemindersButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: _busy
          ? null
          : () async {
              final messenger = ScaffoldMessenger.of(context);
              setState(() => _busy = true);
              try {
                messenger.showSnackBar(SnackBar(content: Text(await Repo.testReminders(widget.leadId))));
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('❌ $e')));
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      icon: _busy
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.alarm_rounded, size: 16),
      label: const Text('Test reminders now'),
    );
  }
}

class _CallbackCard extends StatelessWidget {
  const _CallbackCard({required this.leadId, required this.callback, this.phone});
  final String leadId;
  final Map<String, dynamic> callback;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    final kind = callback['kind'] == 'meet' ? 'Video meeting' : 'Phone call';
    final at = Ist.fromTimestamp(callback['startAt']);
    final brief = '${callback['brief'] ?? ''}';
    return InsightCard(
      title: 'Talk-to-a-human request',
      icon: callback['kind'] == 'meet' ? Icons.videocam_rounded : Icons.phone_callback_rounded,
      accent: AppTheme.human,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(at == null ? '$kind · call back as soon as possible' : '$kind · ${Ist.full(at)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        if (brief.isNotEmpty) ...[const SizedBox(height: 6), Text('“$brief”', style: const TextStyle(fontSize: 13, height: 1.45))],
        if (at != null) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _TestRemindersButton(leadId: leadId),
            _ReminderDot(done: callback['reminded24'] == true, label: '24 h reminder'),
            _ReminderDot(done: callback['reminded1'] == true, label: '1 h reminder'),
          ]),
        ],
        if (phone != null && phone!.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => launchUrl(Uri.parse('tel:+91$phone')), icon: const Icon(Icons.call_rounded, size: 16), label: Text('Call +91 $phone')),
          ),
      ]),
    );
  }
}

class _CallTaskCard extends StatelessWidget {
  const _CallTaskCard({required this.leadId, required this.task, required this.phone, required this.me});
  final String leadId;
  final Map<String, dynamic> task;
  final String? phone;
  final String me;

  @override
  Widget build(BuildContext context) {
    return InsightCard(
      title: 'Call task from the follow-up engine',
      icon: Icons.phone_in_talk_rounded,
      accent: AppTheme.hot,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${task['reason'] ?? ''}', style: const TextStyle(fontSize: 13, height: 1.45)),
        if ((task['script'] as String?)?.isNotEmpty == true) ...[
          const SizedBox(height: 6),
          Text('Say: “${task['script']}”', style: TextStyle(fontSize: 12.5, height: 1.45, color: context.scheme.onSurfaceVariant)),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          if (phone != null && phone!.isNotEmpty)
            FilledButton.icon(onPressed: () => launchUrl(Uri.parse('tel:+91$phone')), icon: const Icon(Icons.call_rounded, size: 16), label: const Text('Call now')),
          OutlinedButton(onPressed: () => _logDialog(context, leadId, me, 'call'), child: const Text('Log the call')),
        ]),
      ]),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.leadId});
  final String leadId;

  @override
  Widget build(BuildContext context) {
    return InsightCard(
      title: 'Book a demo for them',
      icon: Icons.event_rounded,
      child: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: Repo.watchSlots('demo'),
        builder: (context, snap) {
          final slots = (snap.data ?? const []).take(6).toList();
          if (slots.isEmpty) {
            return Text('No open demo slots. Admin → Demo data → Demo-class slots.', style: context.texts.bodySmall?.copyWith(fontSize: 12.5));
          }
          return Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in slots)
              ActionChip(
                label: Text('${s.data()['courseId'] ?? ''} · ${Ist.full(Ist.fromTimestamp(s.data()['startAt']) ?? DateTime.now())}', style: const TextStyle(fontSize: 11.5)),
                onPressed: () => _run(context, () => Repo.book(leadId, s.id), 'Demo booked'),
              ),
          ]);
        },
      ),
    );
  }
}

class _AssignCard extends StatelessWidget {
  const _AssignCard({required this.leadId, this.assignedUid, this.assignedTo, this.lang});
  final String leadId;
  final String? assignedUid;
  final String? assignedTo;
  final String? lang;

  @override
  Widget build(BuildContext context) {
    return InsightCard(
      title: 'Counsellor',
      icon: Icons.assignment_ind_rounded,
      trailing: lang == null ? null : SmallChip('by language: $lang'),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: TeamService.watchTeam(),
        builder: (context, snap) {
          final team = snap.data?.docs ?? const [];
          final known = team.any((t) => t.id == assignedUid);
          return Row(children: [
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: known ? assignedUid : null,
                hint: Text(assignedTo?.isNotEmpty == true ? assignedTo! : 'Not assigned yet', style: const TextStyle(fontSize: 13)),
                underline: const SizedBox.shrink(),
                items: [
                  for (final t in team)
                    DropdownMenuItem(
                      value: t.id,
                      child: Text(
                        '${t.data()['name'] ?? t.data()['email'] ?? 'Counsellor'} · ${((t.data()['languages'] as List?) ?? const ['en']).join('/')}',
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (uid) {
                  if (uid != null) _run(context, () => Repo.assign(leadId, uid), 'Re-assigned');
                },
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _LogTouchCard extends StatelessWidget {
  const _LogTouchCard({required this.leadId, required this.me});
  final String leadId;
  final String me;

  @override
  Widget build(BuildContext context) {
    return InsightCard(
      title: 'Log something that happened outside the app',
      icon: Icons.edit_note_rounded,
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: () => _logDialog(context, leadId, me, 'call'), icon: const Icon(Icons.call_rounded, size: 16), label: const Text('Phone call')),
        OutlinedButton.icon(onPressed: () => _logDialog(context, leadId, me, 'instagram'), icon: const Icon(Icons.camera_alt_outlined, size: 16), label: const Text('Instagram DM')),
        OutlinedButton.icon(onPressed: () => _logDialog(context, leadId, me, 'walkin'), icon: const Icon(Icons.storefront_rounded, size: 16), label: const Text('Visit')),
      ]),
    );
  }
}

Future<void> _logDialog(BuildContext context, String leadId, String me, String channel) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(channel == 'call' ? 'Log a phone call' : channel == 'instagram' ? 'Log an Instagram DM' : 'Log a visit'),
      content: TextField(controller: c, autofocus: true, maxLines: 3, decoration: const InputDecoration(hintText: 'What was said / what happens next')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
      ],
    ),
  );
  if (ok == true && c.text.trim().isNotEmpty) await Repo.logTouch(leadId, channel: channel, note: c.text.trim(), me: me);
  c.dispose();
}

class _ReminderDot extends StatelessWidget {
  const _ReminderDot({required this.done, required this.label});
  final bool done;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = done ? AppTheme.success : context.scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(done ? Icons.check_circle_rounded : Icons.schedule_rounded, size: 13, color: c),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
      ]),
    );
  }
}


// ------------------------------------------------- AI trouble / delivery / intake
/// Asha could not reach any AI provider: the person got a knowledge-base answer and a retry is queued.
class _AiTroubleCard extends StatelessWidget {
  const _AiTroubleCard({required this.ai});
  final Map<String, dynamic> ai;

  @override
  Widget build(BuildContext context) {
    final retryAt = Ist.fromTimestamp(ai['retryAt']);
    final err = '${ai['lastError'] ?? ''}'.split('\n');
    return InsightCard(
      title: 'Asha could not reach the AI',
      icon: Icons.cloud_off_rounded,
      accent: AppTheme.warm,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'They got an instant answer from the knowledge base. '
          '${retryAt != null ? 'Asha retries at ${Ist.time(retryAt)}. ' : ''}Reply from the desk if it is urgent, and check Admin → AI engine → Test.',
          style: context.texts.bodySmall?.copyWith(fontSize: 12.5),
        ),
        const SizedBox(height: 6),
        for (final line in err.skip(err.length > 1 ? 1 : 0).take(4))
          Text('• $line', style: context.texts.bodySmall?.copyWith(fontSize: 11.5, fontFamily: 'monospace')),
      ]),
    );
  }
}

/// The last reply could not be delivered on WhatsApp / Telegram / Instagram, and why.
class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.issue});
  final Map<String, dynamic> issue;

  @override
  Widget build(BuildContext context) {
    final note = '${issue['note'] ?? ''}';
    final testNumber = note.contains('131030') || note.toLowerCase().contains('allowed list');
    return InsightCard(
      title: 'Reply not delivered on ${issue['channel'] ?? 'the channel'}',
      icon: Icons.mark_chat_unread_outlined,
      accent: AppTheme.hot,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(note, style: context.texts.bodySmall?.copyWith(fontSize: 12.5, fontFamily: 'monospace')),
        const SizedBox(height: 6),
        Text(
          testNumber
              ? 'Meta test number: add this person\'s WhatsApp number in Meta → WhatsApp → API Setup → "To" (up to 5 numbers), then reply again.'
              : 'Check Admin → Channels (token / bot), or call them. The conversation is safe here either way.',
          style: context.texts.bodySmall?.copyWith(fontSize: 12),
        ),
      ]),
    );
  }
}

/// The intake answers: who is writing, the student, contact, course picked.
class _IntakeCard extends StatelessWidget {
  const _IntakeCard({required this.ob, required this.d});
  final Map<String, dynamic> ob;
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) {
    final step = '${ob['step'] ?? ''}';
    final done = step == 'done';
    final relation = '${ob['relation'] ?? '-'}';
    final contact = [ob['phone'], ob['email']].whereType<String>().where((x) => x.isNotEmpty).join(' · ');
    final course = ob['courseId'] as String?;
    final rows = <(String, String)>[
      ('Writing', relation == 'self' ? 'the student' : relation),
      ('Student', '${ob['studentName'] ?? d['studentName'] ?? '-'}'),
      ('Student contact', contact.isEmpty ? (d['studentPhone'] as String? ?? 'skipped') : contact),
      ('Course picked', course ?? (ob['wantsHelp'] == true ? 'wants help choosing' : '-')),
      if ((ob['firstQuestion'] as String?)?.isNotEmpty == true) ('First asked', '${ob['firstQuestion']}'),
    ];
    return InsightCard(
      title: done ? 'Intake answers' : 'Intake in progress',
      icon: Icons.assignment_outlined,
      accent: done ? AppTheme.success : AppTheme.info,
      trailing: SmallChip(
        done ? (ob['outcome'] == 'completed' ? 'completed' : 'handed to Asha (${ob['outcome'] ?? ''})') : 'waiting: $step',
        color: done ? AppTheme.success : AppTheme.info,
      ),
      child: Column(children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 118, child: Text(r.$1, style: context.texts.bodySmall?.copyWith(fontSize: 12))),
              Expanded(child: Text(r.$2, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.8))),
            ]),
          ),
      ]),
    );
  }
}

/// The latest questions this person asked, in their own words.
class _QuestionsCard extends StatelessWidget {
  const _QuestionsCard({required this.questions});
  final List<Map<String, dynamic>> questions;

  @override
  Widget build(BuildContext context) {
    return InsightCard(
      title: 'Questions asked',
      icon: Icons.forum_outlined,
      accent: AppTheme.ai,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final q in questions.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('“', style: TextStyle(color: AppTheme.ai.withValues(alpha: 0.7), fontWeight: FontWeight.w800, fontSize: 16, height: 1)),
              const SizedBox(width: 4),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${q['text'] ?? ''}', style: const TextStyle(fontSize: 13, height: 1.35)),
                  Text(
                    '${q['channel'] ?? ''}${Ist.fromTimestamp(q['at']) == null ? '' : ' · ${Ist.relative(Ist.fromTimestamp(q['at']))}'}',
                    style: context.texts.bodySmall?.copyWith(fontSize: 11),
                  ),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Earlier records of the same person or family: any lead sharing a phone or an email
/// (writer's, student's or another contact's), with the questions they asked.
class _HistoryCard extends StatefulWidget {
  const _HistoryCard({required this.leadId, required this.d, required this.me});
  final String leadId;
  final Map<String, dynamic> d;
  final String me;

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _future;
  String _key = '';

  List<String> get _phones {
    final d = widget.d;
    final all = <String>{
      for (final p in [d['phone'], d['studentPhone'], ...((d['contactPhones'] as List?) ?? const [])])
        if (p is String && p.replaceAll(RegExp(r'[^0-9]'), '').length >= 10) p.replaceAll(RegExp(r'[^0-9]'), '').substring(p.replaceAll(RegExp(r'[^0-9]'), '').length - 10),
    };
    return all.take(10).toList();
  }

  List<String> get _emails => <String>{
        for (final e in [widget.d['email'], widget.d['studentEmail']])
          if (e is String && e.contains('@')) e.trim().toLowerCase(),
      }.toList();

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _load() async {
    final leads = FirebaseFirestore.instance.collection('leads');
    final queries = <Future<QuerySnapshot<Map<String, dynamic>>>>[
      if (_phones.isNotEmpty) leads.where('contactPhones', arrayContainsAny: _phones).limit(15).get(),
      for (final p in _phones.take(3)) leads.where('phone', isEqualTo: p).limit(10).get(),
      for (final e in _emails) leads.where('email', isEqualTo: e).limit(10).get(),
      for (final e in _emails) leads.where('studentEmail', isEqualTo: e).limit(10).get(),
    ];
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final snap in await Future.wait(queries)) {
      for (final doc in snap.docs) {
        if (doc.id != widget.leadId) byId[doc.id] = doc;
      }
    }
    final list = byId.values.toList()
      ..sort((a, b) => ((a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0).compareTo((b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final key = '${_phones.join(',')}|${_emails.join(',')}';
    if (key != _key) {
      _key = key;
      _future = (_phones.isEmpty && _emails.isEmpty) ? Future.value(<QueryDocumentSnapshot<Map<String, dynamic>>>[]) : _load();
    }
    final merged = ((widget.d['mergedFromIds'] as List?) ?? const []).length;
    return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      future: _future,
      builder: (context, snap) {
        final others = snap.data ?? const [];
        if (others.isEmpty && merged == 0) return const SizedBox.shrink();
        return InsightCard(
          title: 'Earlier records (same phone or email)',
          icon: Icons.history_rounded,
          accent: AppTheme.human,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (merged > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('This timeline already includes $merged earlier enquir${merged == 1 ? 'y' : 'ies'} merged into it (same person).',
                    style: context.texts.bodySmall?.copyWith(fontSize: 12.5)),
              ),
            for (final o in others) _row(context, o),
          ]),
        );
      },
    );
  }

  Widget _row(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> o) {
    final x = o.data();
    final mergedInto = x['mergedInto'] as String?;
    final created = Ist.fromTimestamp(x['createdAt']);
    final qs = ((x['recentQuestions'] as List?) ?? const []).whereType<Map>().map((m) => '${m['text'] ?? ''}').where((t) => t.isNotEmpty).toList();
    final summary = ((x['summary'] as List?) ?? const []).map((e) => '$e').toList();
    final student = (x['studentName'] as String?)?.isNotEmpty == true ? ' · student ${x['studentName']}' : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.r12),
        border: Border.all(color: context.scheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${x['name'] ?? '(no name)'}$student', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          if (mergedInto == null)
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (ctx) => Scaffold(body: SafeArea(child: LeadDetail(leadId: o.id, me: widget.me, onClose: () => Navigator.of(ctx).pop()))),
              )),
              child: const Text('Open'),
            ),
        ]),
        Text(
          [
            '${x['firstSource'] ?? ''}',
            if (created != null) Ist.relative(created),
            '${x['status'] ?? ''}',
            if (mergedInto == widget.leadId) 'merged here' else if (mergedInto != null) 'merged elsewhere',
          ].where((t) => t.isNotEmpty).join(' · '),
          style: context.texts.bodySmall?.copyWith(fontSize: 11.5),
        ),
        if (qs.isNotEmpty || summary.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            qs.isNotEmpty ? 'Asked: ${qs.reversed.take(3).map((q) => '“$q”').join('  ')}' : summary.first,
            style: context.texts.bodySmall?.copyWith(fontSize: 12, color: context.scheme.onSurface),
          ),
        ],
      ]),
    );
  }
}
