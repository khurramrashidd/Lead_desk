import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config.dart';
import '../data/seed.dart';
import '../services/repo.dart';
import '../utils/responsive.dart';

/// Admin & demo tools: the institute controls the knowledge base here.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _kb = TextEditingController();
  bool _kbLoaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Repo.db.doc('kb/main').get().then((s) {
      final data = Map<String, dynamic>.from(s.data() ?? sampleKnowledgeBase)..remove('updatedAt');
      if (!mounted) return;
      setState(() {
        _kb.text = const JsonEncoder.withIndent('  ').convert(data);
        _kbLoaded = true;
      });
    });
  }

  Future<void> _run(String label, Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
      _snack('✅ $label');
    } catch (e) {
      _snack('❌ $label failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveKb() async {
    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(_kb.text) as Map<String, dynamic>;
      if (parsed['courses'] is! List) throw const FormatException('"courses" must be a list');
    } catch (e) {
      _snack('Not valid JSON: $e');
      return;
    }
    await _run('Knowledge base saved. The AI uses it from the next message.', () async {
      await Repo.db.doc('kb/main').set({...parsed, 'updatedAt': FieldValue.serverTimestamp()});
    });
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  void dispose() {
    _kb.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Admin & demo tools')),
      body: MaxWidth(
        width: 980,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy) const LinearProgressIndicator(),
            _section(
              '1. Demo data',
              'Loads the sample courses, a 7-day demo-class calendar and realistic leads for the dashboard and reports.',
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run('All demo data loaded', () async {
                            await Seed.loadKnowledgeBase();
                            await Seed.loadSlots();
                            await Seed.loadDemoLeads();
                          }),
                  child: const Text('Load everything'),
                ),
                OutlinedButton(onPressed: _busy ? null : () => _run('Courses loaded', Seed.loadKnowledgeBase), child: const Text('Courses only')),
                OutlinedButton(onPressed: _busy ? null : () => _run('Demo slots created', () async => await Seed.loadSlots()), child: const Text('Demo-class slots')),
                OutlinedButton(onPressed: _busy ? null : () => _run('Demo leads loaded', Seed.loadDemoLeads), child: const Text('Demo leads')),
              ]),
            ),
            _section(
              '2. Channel links & QR codes',
              'Each link tags its source, so reports show which channel brings admissions. Put the QR on the projector for judges.',
              Wrap(spacing: 16, runSpacing: 16, children: [
                _qr('Web chat', chatLink('qr')),
                _qr('Instagram bio link', chatLink('instagram')),
                _qr('Website form', formLink('form')),
              ]),
            ),
            _section(
              '3. Time machine (demo)',
              'Moves the server clock forward and runs reminders and follow-ups immediately, so judges see "no lead forgotten" without waiting.',
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: Repo.watchDemoConfig(),
                builder: (context, snap) {
                  final offset = (snap.data?.data()?['clockOffsetMinutes'] as num?)?.toInt() ?? 0;
                  final last = snap.data?.data()?['lastRun'];
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Clock offset: ${offset ~/ 60} h ${offset % 60} min${last == null ? '' : '   ·   last run: $last'}'),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      FilledButton.tonal(onPressed: () => Repo.fastForward(hours: 24), child: const Text('+1 day')),
                      FilledButton.tonal(onPressed: () => Repo.fastForward(hours: 48), child: const Text('+2 days')),
                      OutlinedButton(onPressed: () => Repo.fastForward(hours: 0), child: const Text('Reset')),
                    ]),
                  ]);
                },
              ),
            ),
            _section(
              '4. Knowledge base (the institute controls this)',
              'The AI may only quote fees, EMIs, scholarships, batches and policies written here. Edit, then Save.',
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (!_kbLoaded) const LinearProgressIndicator(),
                TextField(
                  controller: _kb,
                  minLines: 12,
                  maxLines: 24,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                  decoration: const InputDecoration(hintText: '{ "instituteName": ..., "courses": [...] }'),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  FilledButton.icon(icon: const Icon(Icons.save), label: const Text('Save knowledge base'), onPressed: _busy ? null : _saveKb),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() => _kb.text = const JsonEncoder.withIndent('  ').convert(sampleKnowledgeBase)),
                    child: const Text('Reset to sample'),
                  ),
                ]),
              ]),
            ),
            _section(
              '5. WhatsApp',
              'Webhook URL: the "whatsappWebhook" function URL (shown after deploy). Verify token: the WA_VERIFY_TOKEN value in functions/.env.',
              Text('Test number messages reach up to 5 verified phones. Use your own phones in the demo.',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qr(String label, String url) => SizedBox(
        width: 200,
        child: Column(children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(8),
            child: QrImageView(data: url, size: 170),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 14),
            label: const Text('Copy link'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              _snack('Copied $url');
            },
          ),
        ]),
      );

  Widget _section(String title, String help, Widget child) => Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(help, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );
}
