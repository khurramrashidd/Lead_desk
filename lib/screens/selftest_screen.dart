import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../app_theme.dart';
import '../services/api.dart';
import '../services/auth_service.dart';
import '../services/repo.dart';
import 'desk/lead_detail.dart';

/// One row per sentence of the PS3 "What to Build", with how it is solved and a live test.
class _Scenario {
  const _Scenario(this.id, this.title, this.quote, this.how, {this.optional = false, this.seconds = 30});
  final String id;
  final String title;
  final String quote;
  final String how;
  final bool optional;
  final int seconds;
}

const _scenarios = [
  _Scenario('counselling', 'Genuine counselling, not a FAQ bot', '“holds genuine counselling conversations … a prospective student’s real question is rarely “what is the fee?”',
      'Sends the sponsor’s exact question (commerce graduate, two-year gap). Asha must answer the worry, not list fees, and ask a question back. Prompt + conversation state in functions/src/brain.ts.'),
  _Scenario('languages', 'English, Hindi and Marathi', '“understand text … in English, Hindi and Marathi”',
      'Three new prospects write in English, Hindi and Marathi. Each reply must come back in the same language (checked by script and word markers, and by the language the AI tagged).'),
  _Scenario('codemix', 'Mid-sentence language switches', '“including mid-sentence switches between them”',
      'Hinglish and Marathi-English messages. The reply must keep the same blend and the Latin script, not jump to pure English or Devanagari.'),
  _Scenario('register', 'Same register (aap / tu)', '“reply in the language and register the prospect uses”',
      'A casual “bhai tu bata” message and a formal “कृपया बताइए” message. The AI must detect casual vs formal, and the formal reply must use “आप”.'),
  _Scenario('voice', 'Voice notes', '“understand … voice notes”',
      'Sends a Marathi voice note (WhatsApp) and a Hindi voice note (Telegram). Gemini hears audio directly (Groq Whisper if Gemini is busy); the transcript is saved on the message and the reply is in the same language.',
      seconds: 45),
  _Scenario('profile', 'Background, goals, constraints', '“ask about background, goals and constraints”',
      'A prospect shares education, work, timing, budget and family view. They must be captured in the lead profile (“What we know” on the desk) and raised as objections.'),
  _Scenario('kb', 'Answers strictly from the knowledge base', '“answer course, fee and schedule questions strictly from a knowledge base the institute controls”',
      'Asks fee, EMI and next batch. The reply must quote the exact numbers from kb/main (Admin → Knowledge base), which the website also reads.'),
  _Scenario('guard', 'Never invents discounts, fees or guarantees', '“never invent discounts, fees or placement guarantees, even when pressed”',
      'First proves the Guard blocks 5 invented drafts (EN/Hinglish/Marathi). Then presses Asha three times (friend got 30%, 20% final offer, job guarantee). Every reply must pass the Guard. functions/src/guard.ts',
      seconds: 45),
  _Scenario('aptitude', 'Short adaptive aptitude check', '“run a short adaptive aptitude check”',
      'Starts the check in the chat and answers right, wrong, right, right. The server scores each answer and the next question must get harder after a right answer and easier after a wrong one. functions/src/aptitude.ts',
      seconds: 90),
  _Scenario('recommend', 'Honest recommendation', '“recommend a program with an honest reason”',
      'A 12th-commerce beginner with little time and money asks which course. Asha must pick one course from the knowledge base with a specific reason, not the most expensive one.'),
  _Scenario('booking', 'Real calendar slot + reminders', '“book a demo class into a real calendar slot with reminders”',
      'Books a demo by chat: a seat is reserved in a slot (transaction), the event is created in Google Calendar (if connected), then the real heartbeat is run for this lead at 23 h and 30 min before the class to prove both reminders fire.',
      seconds: 60),
  _Scenario('identity', 'Rahul Patil = राहुल पाटल (one timeline)', '“a form submission from “Rahul Patil” and a WhatsApp message from “राहुल पाटल” with a differently formatted phone number are the same person”',
      'Website form as Rahul Patil (0XXXXX XXXXX), then a WhatsApp message through the real webhook parser as राहुल पाटल (91XXXXXXXXXX). Must merge into one timeline. Also: father and friend for the same student → same lead; same father for his daughter → separate linked lead; another Rahul Patil → not merged.'),
  _Scenario('nba', 'Next-best-action engine', '“decide when, on which channel and with what message to follow up … based on their behaviour and the objections they have raised”',
      'Two prospects: one with a family-approval objection, one with a fees objection. Each must get a different playbook, a time outside 9 PM–9 AM, a channel and a message; then the follow-up fires automatically when due. functions/src/nba.ts'),
  _Scenario('dashboard', 'Live dashboard data', '“every lead with a score, a three-line summary, detected objections — fees, job fears, family approval — and a suggested next message”',
      'A prospect with all three worries. The lead must have an explainable score, exactly three summary lines, the three objections, a suggested message and an assigned counsellor.'),
  _Scenario('takeover', 'Take over instantly', '“able to take over any conversation instantly”',
      'Takes over a live conversation, then the prospect writes again: Asha must not reply, the desk must flag it for the human, and the counsellor’s reply lands in the same chat.'),
  _Scenario('channels', 'Every enquiry in one place', '“keeps every enquiry in one place … WhatsApp, phone calls, Instagram, website forms and walk-ins”',
      'One enquiry per channel (web, form, Google Form, walk-in, call, WhatsApp, Telegram, Instagram). All must land in the same lead list with their source.',
      seconds: 15),
  _Scenario('telephony', 'Phone calls (optional)', '“answer and make phone calls through an Indian telephony provider”',
      'A missed call arrives in the same format the call webhook builds from Exotel/Twilio/Plivo and becomes a “call” lead that Asha follows up. Provider account not connected (KYC), so this is simulated.',
      optional: true),
  _Scenario('instagram', 'Instagram DMs (optional)', '“capture Instagram direct messages”',
      'Feeds an Instagram webhook payload through the real parser: it must become an Instagram lead and get a reply. Real DMs need a Professional account.',
      optional: true),
  _Scenario('reports', 'Conversion reports', '“report conversion by source, counselor and objection”',
      'Computes conversion by source, counsellor and objection over the real leads (Desk → Reports shows the same charts).',
      optional: true, seconds: 10),
  _Scenario('scale', 'Scale: same question, one AI call', 'Beyond the statement: thousands of enquiries at once',
      'Two strangers send the identical question at the same moment. One AI call must serve both (single-flight cache), and they must stay two separate leads.'),
];

class SelfTestScreen extends StatefulWidget {
  const SelfTestScreen({super.key});

  @override
  State<SelfTestScreen> createState() => _SelfTestScreenState();
}

class _SelfTestScreenState extends State<SelfTestScreen> {
  bool _runningAll = false;
  String? _current;

  DocumentReference<Map<String, dynamic>> _doc(String id) => Repo.db.doc('selftests/$id');

  Future<void> _start(String id) async {
    await _doc(id).set({
      'scenario': id,
      'status': 'queued',
      'runToken': '${DateTime.now().microsecondsSinceEpoch}',
      'requestedBy': AuthService.displayName,
      'requestedAt': FieldValue.serverTimestamp(),
      'checks': <Object>[],
      'evidence': <Object>[],
      'leadIds': <Object>[],
    });
  }

  Future<void> _runAll() async {
    setState(() => _runningAll = true);
    try {
      for (final s in _scenarios) {
        if (!mounted || !_runningAll) break;
        setState(() => _current = s.id);
        await _start(s.id);
        await _doc(s.id)
            .snapshots()
            .firstWhere((d) => const ['pass', 'fail', 'warn', 'error'].contains(d.data()?['status']))
            .timeout(const Duration(minutes: 9), onTimeout: () => throw TimeoutException('timed out'));
      }
    } catch (e) {
      _snack('Stopped: $e');
    } finally {
      if (mounted) {
        setState(() {
          _runningAll = false;
          _current = null;
        });
      }
    }
  }

  Future<void> _copyReport() async {
    final b = StringBuffer('# AI Lead Desk — PS3 self-test report\n\n');
    for (final s in _scenarios) {
      final d = (await _doc(s.id).get()).data();
      final status = '${d?['status'] ?? 'not run'}'.toUpperCase();
      b.writeln('## ${s.title} — $status');
      b.writeln('> ${s.quote}\n');
      b.writeln('${s.how}\n');
      for (final c in (d?['checks'] as List? ?? const [])) {
        final m = (c as Map).cast<String, dynamic>();
        final icon = m['ok'] == true ? '✅' : m['ok'] == false ? '❌' : '⚠️';
        b.writeln('- $icon ${m['label']}${(m['detail'] as String?)?.isNotEmpty == true ? ' — ${m['detail']}' : ''}');
      }
      final ev = (d?['evidence'] as List? ?? const []);
      if (ev.isNotEmpty) {
        b.writeln('\nEvidence:');
        for (final e in ev) {
          final m = (e as Map).cast<String, dynamic>();
          b.writeln('- **${m['who']}**: ${'${m['text']}'.replaceAll('\n', ' ')}${m['note'] != null ? ' _(${m['note']})_' : ''}');
        }
      }
      b.writeln();
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    _snack('Report copied (Markdown). Paste it into your submission or a doc.');
  }

  Future<void> _cleanup() async {
    try {
      final r = await Api.run('selftestCleanup');
      _snack('Removed ${r['removed']} self-test leads and all results.');
    } catch (e) {
      _snack('❌ $e');
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      backgroundColor: context.scheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('PS3 self-test · proof'),
        actions: [
          IconButton(tooltip: 'Copy report', onPressed: _copyReport, icon: const Icon(Icons.copy_all_rounded)),
          IconButton(tooltip: 'Clean up test leads', onPressed: _runningAll ? null : _cleanup, icon: const Icon(Icons.cleaning_services_outlined)),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: phone ? 12 : 24, vertical: 16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: context.scheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.r16),
                    border: Border.all(color: context.scheme.outlineVariant),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Every sentence of “What to Build”, tested live', style: context.texts.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      'Each test talks to the real AI, the real database and the real triggers, then records checks and the actual '
                      'conversation as evidence. Test leads use simulated channel ids (nothing is sent to a real phone) and are marked '
                      '“self-test”. Run them one by one, or all in order (about 8–12 minutes on free AI keys).',
                      style: context.texts.bodyMedium?.copyWith(fontSize: 13.5),
                    ),
                    const SizedBox(height: 14),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      FilledButton.icon(
                        onPressed: _runningAll ? () => setState(() => _runningAll = false) : _runAll,
                        style: FilledButton.styleFrom(backgroundColor: _runningAll ? AppTheme.hot : AppTheme.coral),
                        icon: Icon(_runningAll ? Icons.stop_rounded : Icons.playlist_play_rounded),
                        label: Text(_runningAll ? 'Stop after this test' : 'Run all, one by one'),
                      ),
                      OutlinedButton.icon(onPressed: _copyReport, icon: const Icon(Icons.copy_all_rounded, size: 18), label: const Text('Copy report')),
                    ]),
                  ]),
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < _scenarios.length; i++)
                  _ScenarioCard(
                    index: i + 1,
                    s: _scenarios[i],
                    stream: _doc(_scenarios[i].id).snapshots(),
                    highlighted: _current == _scenarios[i].id,
                    onRun: _runningAll ? null : () => _start(_scenarios[i].id),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({required this.index, required this.s, required this.stream, required this.onRun, this.highlighted = false});
  final int index;
  final _Scenario s;
  final Stream<DocumentSnapshot<Map<String, dynamic>>> stream;
  final VoidCallback? onRun;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        final d = snap.data?.data();
        final status = '${d?['status'] ?? 'not run'}';
        final checks = ((d?['checks'] as List?) ?? const []).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
        final evidence = ((d?['evidence'] as List?) ?? const []).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
        final leads = ((d?['leadIds'] as List?) ?? const []).map((e) => '$e').toList();
        final running = status == 'queued' || status == 'running';
        final color = switch (status) {
          'pass' => AppTheme.success,
          'warn' => AppTheme.warm,
          'fail' || 'error' => AppTheme.hot,
          'running' || 'queued' => AppTheme.info,
          _ => AppTheme.cold,
        };
        final ms = (d?['ms'] as num?)?.toInt();
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: context.scheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.r16),
            border: Border.all(color: highlighted ? AppTheme.info : context.scheme.outlineVariant, width: highlighted ? 1.6 : 1),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: running || status == 'fail' || status == 'error',
              tilePadding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: color.withValues(alpha: 0.14),
                child: running
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                    : Text('$index', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
              title: Row(children: [
                Expanded(child: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                if (s.optional)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text('optional', style: TextStyle(fontSize: 11, color: context.scheme.onSurfaceVariant)),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                  child: Text(status.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
                ),
              ]),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(s.quote, style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: context.scheme.onSurfaceVariant)),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(s.how, style: context.texts.bodyMedium?.copyWith(fontSize: 13)),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  FilledButton.tonalIcon(
                    onPressed: running ? null : onRun,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(running ? 'Running…' : (d == null ? 'Run this test' : 'Run again')),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      ms != null ? 'took ${(ms / 1000).toStringAsFixed(1)} s · ${d?['aiReplies'] ?? 0} AI replies' : '≈ ${s.seconds} s',
                      style: context.texts.bodySmall?.copyWith(fontSize: 12),
                    ),
                  ),
                ]),
                if (d?['error'] != null) ...[
                  const SizedBox(height: 8),
                  Text('Error: ${d!['error']}', style: const TextStyle(color: AppTheme.hot, fontSize: 12.5)),
                ],
                if (checks.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final c in checks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c['ok'] == true ? '✅' : c['ok'] == false ? '❌' : '⚠️', style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${c['label']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            if ((c['detail'] as String?)?.isNotEmpty == true)
                              SelectableText('${c['detail']}', style: TextStyle(fontSize: 12, color: context.scheme.onSurfaceVariant, height: 1.4)),
                          ]),
                        ),
                      ]),
                    ),
                ],
                if (evidence.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: context.scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(AppTheme.r12)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('EVIDENCE (the real conversation)', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: context.scheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      for (final e in evidence) _EvidenceLine(e),
                    ]),
                  ),
                ],
                if (leads.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final id in leads.take(8))
                      ActionChip(
                        avatar: const Icon(Icons.open_in_new_rounded, size: 15),
                        label: Text('Open lead ${id.substring(0, id.length < 6 ? id.length : 6)}', style: const TextStyle(fontSize: 12)),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (ctx) => Scaffold(
                            body: SafeArea(child: LeadDetail(leadId: id, me: AuthService.displayName, onClose: () => Navigator.of(ctx).pop())),
                          ),
                        )),
                      ),
                  ]),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EvidenceLine extends StatelessWidget {
  const _EvidenceLine(this.e);
  final Map<String, dynamic> e;

  @override
  Widget build(BuildContext context) {
    final who = '${e['who']}';
    final (label, color) = switch (who) {
      'prospect' => ('Prospect', AppTheme.indigo),
      'asha' => ('Asha', AppTheme.ai),
      'counsellor' => ('Counsellor', AppTheme.human),
      _ => ('System', AppTheme.cold),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 78, child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: color))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText('${e['text']}', style: const TextStyle(fontSize: 13, height: 1.45)),
            if (e['note'] != null) Text('${e['note']}', style: TextStyle(fontSize: 11, color: context.scheme.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }
}
