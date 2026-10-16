import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_theme.dart';
import '../../services/repo.dart';
import '../../utils/ist.dart';
import '../../widgets/lead_widgets.dart';
import '../../widgets/message_bubble.dart';

/// Everything about one lead: live conversation + AI insights + take over.
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
        final mergedInto = d['mergedInto'] as String?;
        if (mergedInto != null) {
          return Center(child: Text('This enquiry was merged into another lead (same person).'));
        }
        return LayoutBuilder(builder: (context, c) {
          final header = _Header(leadId: leadId, d: d, me: me, onClose: onClose);
          final chat = _Conversation(leadId: leadId, d: d, me: me);
          final insights = _Insights(leadId: leadId, d: d, me: me);
          if (c.maxWidth >= 880) {
            return Column(children: [
              header,
              const Divider(height: 1),
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(flex: 5, child: chat),
                  const VerticalDivider(width: 1),
                  Expanded(flex: 4, child: insights),
                ]),
              ),
            ]);
          }
          return DefaultTabController(
            length: 2,
            child: Column(children: [
              header,
              const TabBar(tabs: [Tab(text: 'Conversation'), Tab(text: 'AI insights')]),
              Expanded(child: TabBarView(children: [chat, insights])),
            ]),
          );
        });
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.leadId, required this.d, required this.me, this.onClose});
  final String leadId;
  final Map<String, dynamic> d;
  final String me;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = (d['name'] as String?)?.isNotEmpty == true ? d['name'] as String : 'New enquiry';
    final latin = d['nameLatin'] as String?;
    final aliases = (d['aliases'] as List?)?.cast<String>() ?? const <String>[];
    final phone = d['phone'] as String?;
    final paused = d['aiPaused'] == true;
    final status = d['status'] as String? ?? 'new';
    final lang = [d['language'], d['register'], if (d['script'] != null) '${d['script']} script']
        .where((e) => e != null && '$e'.isNotEmpty)
        .join(' · ');

    final actions = <Widget>[
      PopupMenuButton<String>(
        tooltip: 'Status',
        initialValue: status,
        onSelected: (s) => Repo.setStatus(leadId, s),
        itemBuilder: (_) => [for (final e in statusLabels.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
        child: Chip(label: Text(statusLabels[status] ?? status), avatar: const Icon(Icons.flag, size: 16)),
      ),
      const SizedBox(width: 8),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: paused ? AppTheme.ai : AppTheme.human),
        icon: Icon(paused ? Icons.smart_toy : Icons.headset_mic, size: 18),
        label: Text(paused ? 'Hand back to AI' : 'Take over'),
        onPressed: () => Repo.setTakeover(leadId, !paused, me),
      ),
    ];

    final identity = Row(children: [
      if (onClose != null) IconButton(icon: const Icon(Icons.arrow_back), onPressed: onClose),
        CircleAvatar(
          radius: 22,
          backgroundColor: AppTheme.temperature(d['temperature'] as String?).withValues(alpha: 0.15),
          child: Text(initialsOf(latin ?? name), style: TextStyle(color: AppTheme.temperature(d['temperature'] as String?), fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(latin != null && latin != name ? '$name · $latin' : name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(
              [
                if (phone != null) '+91 $phone',
                if (d['city'] != null) '📍 ${d['city']}',
                if (lang.isNotEmpty) '🗣 $lang',
                if (aliases.isNotEmpty) '🔗 also "${aliases.join('", "')}"',
              ].join('   '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ]),
        ),
    ]);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 600) {
          // phone: buttons go on their own row so nothing overflows
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            identity,
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ]);
        }
        return Row(children: [Expanded(child: identity), ...actions]);
      }),
    );
  }
}

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
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    final channel = widget.d['waId'] != null ? 'whatsapp' : 'web';
    await Repo.sendCounsellorMessage(widget.leadId, t, channel: channel, me: widget.me);
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
    final scheme = Theme.of(context).colorScheme;
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
              return Center(child: Text('No messages yet', style: TextStyle(color: scheme.onSurfaceVariant)));
            }
            return ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: docs.length,
              itemBuilder: (context, i) => MessageBubble.fromDoc(docs[i].data()),
            );
          },
        ),
      ),
      if (paused)
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(hintText: 'Reply as ${widget.me}…'),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(icon: const Icon(Icons.send), onPressed: _send),
            ]),
          ),
        )
      else
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          color: AppTheme.ai.withValues(alpha: 0.08),
          child: const Text('🤖 Asha (AI) is replying. Tap "Take over" to reply yourself — the AI stops instantly.',
              textAlign: TextAlign.center),
        ),
    ]);
  }
}

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

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (d['possibleDuplicateOf'] != null)
          _card(context, '⚠️ Possible duplicate', Text('${d['possibleDuplicateReason'] ?? ''}\nLead id: ${d['possibleDuplicateOf']}')),
        if (d['needsHuman'] == true)
          _card(context, '🙋 Needs a human', Text((d['handoffReason'] as String?)?.isNotEmpty == true ? d['handoffReason'] as String : 'The AI asked for help on this one.')),
        Row(children: [
          ScoreBadge(score: (d['score'] as num?)?.toInt() ?? 0, temperature: d['temperature'] as String?, big: true),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              TempChip(d['temperature'] as String?),
              for (final s in (d['sources'] as List?)?.cast<String>() ?? const <String>[]) SmallChip(sourceLabels[s] ?? s),
              if ((d['guardBlocks'] as num?) != null && (d['guardBlocks'] as num) > 0)
                SmallChip('🛡 ${d['guardBlocks']} blocked claims', color: AppTheme.guard),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        _card(
          context,
          '📝 Summary',
          summary.isEmpty
              ? const Text('Appears after the first AI reply.')
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final s in summary) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $s')),
                ]),
        ),
        _card(
          context,
          '🧱 Objections',
          objections.isEmpty
              ? const Text('None detected yet')
              : Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final o in objections) SmallChip(objectionLabels[o] ?? o, color: AppTheme.warm),
                ]),
        ),
        if (suggested != null && suggested.isNotEmpty)
          _card(
            context,
            '💬 Suggested next message',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableText(suggested),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.send, size: 16),
                  label: Text('Send as $me'),
                  onPressed: () => Repo.sendCounsellorMessage(leadId, suggested, channel: channel, me: me),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy'),
                  onPressed: () => Clipboard.setData(ClipboardData(text: suggested)),
                ),
              ]),
            ]),
          ),
        if (na != null)
          _card(
            context,
            '🎯 Next best action',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                na['done'] == true
                    ? '✅ Done'
                    : '${_channelIcon(na['channel'] as String?)} ${Ist.full(Ist.fromTimestamp(na['at']) ?? DateTime.now())}  (${Ist.relative(Ist.fromTimestamp(na['at']))})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if ((na['reason'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text('Why: ${na['reason']}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
              if ((na['message'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text('“${na['message']}”'),
              ],
              if (na['done'] != true && (na['message'] as String?)?.isNotEmpty == true)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () async {
                      await Repo.sendCounsellorMessage(leadId, na['message'] as String, channel: channel, me: me);
                      await Repo.leads.doc(leadId).set({'nextAction': {'done': true}}, SetOptions(merge: true));
                    },
                    child: const Text('Send now'),
                  ),
                ),
            ]),
          ),
        if (rec != null)
          _card(context, '🎓 Recommended program', Text('${rec['courseId']}\n${rec['reason'] ?? ''}')),
        if (apt != null && apt['status'] != 'not_started')
          _card(
            context,
            '🧠 Aptitude check',
            Text('Status: ${apt['status']}   ·   ${apt['correct'] ?? 0}/${apt['questions_asked'] ?? 0} correct   ·   level: ${apt['current_level'] ?? '-'}'
                '${(apt['result'] as String?)?.isNotEmpty == true ? '\n${apt['result']}' : ''}'),
          ),
        if (booking != null)
          _card(
            context,
            '📅 Demo class',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${booking['title']}\n${Ist.full(Ist.fromTimestamp(booking['startAt']) ?? DateTime.now())}'),
              const SizedBox(height: 4),
              Text('Reminders: 24 h ${booking['reminded24'] == true ? '✅' : '⏳'}   1 h ${booking['reminded1'] == true ? '✅' : '⏳'}'),
              if (booking['calendarUrl'] != null)
                TextButton.icon(
                  icon: const Icon(Icons.event, size: 16),
                  label: const Text('Open in Google Calendar'),
                  onPressed: () => launchUrl(Uri.parse(booking['calendarUrl'] as String), mode: LaunchMode.externalApplication),
                ),
            ]),
          ),
        if (profile.isNotEmpty)
          _card(
            context,
            '👤 What we know',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final e in profile.entries)
                if ('${e.value}'.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('${e.key}: ${e.value}')),
            ]),
          ),
      ],
    );
  }

  static String _channelIcon(String? c) => switch (c) {
        'whatsapp' => '🟢',
        'call' => '📞',
        _ => '🌐',
      };

  Widget _card(BuildContext context, String title, Widget child) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            child,
          ]),
        ),
      );
}
