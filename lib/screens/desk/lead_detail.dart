import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_theme.dart';
import '../../services/repo.dart';
import '../../utils/ist.dart';
import '../../widgets/lead_widgets.dart';
import '../../widgets/message_bubble.dart';

/// Everything about one lead: the live conversation, what the AI worked out,
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
          final chat = _Conversation(leadId: leadId, d: d, me: me);
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
                    SizedBox(width: 352, child: insights),
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

    final takeover = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: paused ? AppTheme.ai : AppTheme.human,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      ),
      icon: Icon(paused ? Icons.smart_toy_rounded : Icons.headset_mic_rounded, size: 18),
      label: Text(paused ? 'Hand back to Asha' : 'Take over'),
      onPressed: () => Repo.setTakeover(leadId, !paused, me),
    );

    final statusMenu = PopupMenuButton<String>(
      tooltip: 'Change status',
      initialValue: status,
      onSelected: (s) => Repo.setStatus(leadId, s),
      itemBuilder: (_) => [
        for (final e in statusLabels.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
      ],
      child: StatusPill(status),
    );

    final identity = Row(
      children: [
        if (onClose != null)
          IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: onClose),
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
                  if (d['city'] != null) '📍 ${d['city']}',
                  if (lang.isNotEmpty) '🗣 $lang',
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
            Row(children: [statusMenu, const Spacer(), takeover]),
          ]);
        }
        return Row(children: [
          Expanded(child: identity),
          statusMenu,
          const SizedBox(width: 12),
          takeover,
        ]);
      }),
    );
  }
}

// ----------------------------------------------------------- conversation
class _Conversation extends StatefulWidget {
  const _Conversation({required this.leadId, required this.d, required this.me});
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

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    _text.clear();
    final channel = widget.d['waId'] != null ? 'whatsapp' : 'web';
    await Repo.sendCounsellorMessage(widget.leadId, body, channel: channel, me: widget.me);
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
    return Column(children: [
      Expanded(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _messages,
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
            });
            if (docs.isEmpty) {
              return Center(
                child: Text('No messages yet', style: context.texts.bodyMedium),
              );
            }
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
                  decoration: InputDecoration(hintText: 'Reply as ${widget.me}…'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _send,
                icon: const Icon(Icons.send_rounded),
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(14),
                  backgroundColor: AppTheme.human,
                ),
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

  @override
  Widget build(BuildContext context) {
    final summary = (d['summary'] as List?)?.cast<String>() ?? const <String>[];
    final objections = (d['objections'] as List?)?.cast<String>() ?? const <String>[];
    final suggested = d['suggestedMessage'] as String?;
    final na = (d['nextAction'] as Map?)?.cast<String, dynamic>();
    final rec = (d['recommendation'] as Map?)?.cast<String, dynamic>();
    final apt = (d['aptitude'] as Map?)?.cast<String, dynamic>();
    final booking = (d['booking'] as Map?)?.cast<String, dynamic>();
    final profile = (d['profile'] as Map?)?.cast<String, dynamic>() ?? const {};
    final channel = d['waId'] != null ? 'whatsapp' : 'web';
    final guardBlocks = (d['guardBlocks'] as num?)?.toInt() ?? 0;

    return Container(
      color: context.scheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          if (d['possibleDuplicateOf'] != null)
            InsightCard(
              title: 'Possible duplicate',
              icon: Icons.warning_amber_rounded,
              accent: AppTheme.warm,
              child: Text('${d['possibleDuplicateReason'] ?? ''}\nOther lead: ${d['possibleDuplicateOf']}',
                  style: context.texts.bodyMedium?.copyWith(fontSize: 13)),
            ),
          if (d['needsHuman'] == true)
            InsightCard(
              title: 'Needs a human',
              icon: Icons.pan_tool_rounded,
              accent: AppTheme.hot,
              child: Text(
                (d['handoffReason'] as String?)?.isNotEmpty == true
                    ? d['handoffReason'] as String
                    : 'Asha asked for help on this one.',
                style: context.texts.bodyMedium?.copyWith(fontSize: 13),
              ),
            ),

          // ---- score ----
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.scheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.r16),
              border: Border.all(color: context.scheme.outlineVariant),
            ),
            child: Row(children: [
              ScoreBadge(score: (d['score'] as num?)?.toInt() ?? 0, temperature: d['temperature'] as String?, big: true),
              const SizedBox(width: 14),
              Expanded(
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  TempChip(d['temperature'] as String?),
                  for (final s in (d['sources'] as List?)?.cast<String>() ?? const <String>[])
                    SmallChip(sourceLabels[s] ?? s),
                  if (guardBlocks > 0) SmallChip('🛡 $guardBlocks blocked', color: AppTheme.guard),
                ]),
              ),
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
                      for (final s in summary)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 6, right: 8),
                              child: Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(color: AppTheme.indigo, shape: BoxShape.circle),
                              ),
                            ),
                            Expanded(child: Text(s, style: const TextStyle(fontSize: 13.2, height: 1.45))),
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
                : Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final o in objections) SmallChip(objectionLabels[o] ?? o, color: AppTheme.warm),
                  ]),
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
                  decoration: BoxDecoration(
                    color: AppTheme.indigo.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(AppTheme.r12),
                  ),
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(_channelIcon(na['channel'] as String?), style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      na['done'] == true
                          ? 'Already sent'
                          : Ist.full(Ist.fromTimestamp(na['at']) ?? DateTime.now()),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                  if (na['done'] != true)
                    Text(Ist.relative(Ist.fromTimestamp(na['at'])),
                        style: context.texts.bodySmall?.copyWith(fontSize: 11.5)),
                ]),
                if ((na['reason'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text('Why: ${na['reason']}',
                      style: context.texts.bodySmall?.copyWith(fontSize: 12.5, height: 1.45)),
                ],
                if ((na['message'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text('“${na['message']}”', style: const TextStyle(fontSize: 13, height: 1.45)),
                ],
                if (na['done'] != true && (na['message'] as String?)?.isNotEmpty == true)
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
                Text('${rec['courseId']}'.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, letterSpacing: 0.4)),
                const SizedBox(height: 5),
                Text('${rec['reason'] ?? ''}', style: const TextStyle(fontSize: 13, height: 1.45)),
              ]),
            ),

          if (apt != null && apt['status'] != 'not_started')
            InsightCard(
              title: 'Aptitude check',
              icon: Icons.psychology_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  SmallChip('${apt['status']}'),
                  const SizedBox(width: 6),
                  SmallChip('${apt['correct'] ?? 0}/${apt['questions_asked'] ?? 0} correct'),
                  const SizedBox(width: 6),
                  SmallChip('level ${apt['current_level'] ?? '-'}'),
                ]),
                if ((apt['result'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text('${apt['result']}', style: const TextStyle(fontSize: 13, height: 1.45)),
                ],
              ]),
            ),

          if (booking != null)
            InsightCard(
              title: 'Demo class',
              icon: Icons.event_available_rounded,
              accent: AppTheme.human,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${booking['title']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 3),
                Text(Ist.full(Ist.fromTimestamp(booking['startAt']) ?? DateTime.now()),
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 10),
                Row(children: [
                  _ReminderDot(done: booking['reminded24'] == true, label: '24 h'),
                  const SizedBox(width: 8),
                  _ReminderDot(done: booking['reminded1'] == true, label: '1 h'),
                ]),
                if (booking['calendarUrl'] != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: const Text('Google Calendar'),
                      onPressed: () =>
                          launchUrl(Uri.parse(booking['calendarUrl'] as String), mode: LaunchMode.externalApplication),
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
                            style: const TextStyle(fontSize: 13, height: 1.45),
                            children: [
                              TextSpan(
                                text: '${_pretty(e.key)}: ',
                                style: TextStyle(fontWeight: FontWeight.w700, color: context.scheme.onSurface),
                              ),
                              TextSpan(text: '${e.value}', style: TextStyle(color: context.scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
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
        'call' => '📞',
        _ => '🌐',
      };
}

class _ReminderDot extends StatelessWidget {
  const _ReminderDot({required this.done, required this.label});
  final bool done;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = done ? AppTheme.human : context.scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(done ? Icons.check_circle_rounded : Icons.schedule_rounded, size: 13, color: c),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
      ]),
    );
  }
}
