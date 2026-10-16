import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/repo.dart';
import '../../services/voice_recorder.dart';
import '../../utils/ist.dart';
import '../../utils/responsive.dart';
import '../../widgets/message_bubble.dart';

/// What a student or parent sees after scanning the QR code / opening the link.
/// No app and no login needed. Text or voice notes in English, Hindi or Marathi.
class ProspectChatScreen extends StatefulWidget {
  const ProspectChatScreen({super.key, required this.source, this.leadId});
  final String source; // web, instagram, qr, form ... (used for "which source brings admissions")
  final String? leadId;

  @override
  State<ProspectChatScreen> createState() => _ProspectChatScreenState();
}

class _ProspectChatScreenState extends State<ProspectChatScreen> {
  static const _prefsKey = 'prospect_lead_id';
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = VoiceRecorder();
  String? _leadId;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _messageStream;
  bool _recording = false;
  bool _sending = false;
  Timer? _recTimer;
  StreamSubscription? _leadSub;

  static const _greeting =
      'Namaste 🙏 I\'m Asha, admissions counsellor at TechSummitTrainers. '
      'Type or send a voice note in English, हिंदी or मराठी — whatever feels comfortable!';

  static const _starters = [
    'I\'m a commerce graduate with a 2-year gap — can I really become a developer?',
    'Full Stack Java ki fees kitni hai?',
    'मला डेटा सायन्स शिकायचं आहे',
    'Demo class book karna hai',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final id = widget.leadId ?? prefs.getString(_prefsKey);
    if (id != null) {
      await prefs.setString(_prefsKey, id);
      _follow(id);
    }
  }

  /// If this lead gets merged into another (same person on another channel), follow it.
  void _follow(String id) {
    if (!mounted) return;
    _leadSub?.cancel();
    setState(() {
      _leadId = id;
      _messageStream = Repo.watchMessages(id); // created once, not on every rebuild
    });
    _leadSub = Repo.watchLead(id).listen((snap) async {
      final mergedInto = snap.data()?['mergedInto'] as String?;
      if (mergedInto != null && mergedInto != _leadId) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, mergedInto);
        _follow(mergedInto);
      }
    });
  }

  Future<String> _ensureLead() async {
    if (_leadId != null) return _leadId!;
    final id = await Repo.createLead(source: widget.source);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, id);
    _follow(id);
    return id;
  }

  Future<void> _sendText([String? preset]) async {
    final t = (preset ?? _text.text).trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final id = await _ensureLead();
      _text.clear();
      await Repo.sendProspectMessage(id, text: t);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      _recTimer?.cancel();
      setState(() => _recording = false);
      final note = await _recorder.stop();
      if (note == null) {
        _snack('Voice note too short or too long. Try again (max ${_recorder.maxSeconds}s).');
        return;
      }
      final id = await _ensureLead();
      await Repo.sendProspectMessage(id, audioB64: note.base64, audioMime: note.mime, text: '🎤 Voice note (${note.seconds}s)');
      return;
    }
    final ok = await _recorder.start();
    if (!ok) {
      _snack('Please allow microphone access to send a voice note.');
      return;
    }
    setState(() => _recording = true);
    _recTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {});
      if (_recorder.elapsedSeconds >= _recorder.maxSeconds) _toggleRecording();
    });
  }

  Future<void> _cancelRecording() async {
    _recTimer?.cancel();
    await _recorder.cancel();
    if (mounted) setState(() => _recording = false);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    _leadSub?.cancel();
    _recorder.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          CircleAvatar(backgroundColor: scheme.primary, child: const Text('A', style: TextStyle(color: Colors.white))),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Asha · TechSummitTrainers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text('Admissions counsellor · replies 24×7',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ]),
        ]),
        actions: const [Padding(padding: EdgeInsets.only(right: 12), child: Center(child: IstClock(compact: true)))],
      ),
      body: MaxWidth(
        child: Column(
          children: [
            Expanded(child: _leadId == null ? _welcome() : _messages()),
            _inputBar(scheme),
          ],
        ),
      ),
    );
  }

  Widget _welcome() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const MessageBubble(role: 'ai', text: _greeting),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final s in _starters) ActionChip(label: Text(s), onPressed: () => _sendText(s))],
          ),
        ],
      );

  Widget _messages() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _messageStream,
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final visible = docs.where((d) => d.data()['role'] != 'system' || d.data()['meta']?['kind'] == 'takeover').toList();
        final last = visible.isEmpty ? null : visible.last.data();
        final lastAt = Ist.fromTimestamp(last?['createdAt']) ?? DateTime.now();
        final waiting = last != null && last['role'] == 'user' && DateTime.now().difference(lastAt).inSeconds < 90;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(_scroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
          }
        });
        return ListView(
          controller: _scroll,
          padding: const EdgeInsets.all(16),
          children: [
            const MessageBubble(role: 'ai', text: _greeting),
            for (final d in visible)
              MessageBubble.fromDoc(d.data(), prospectView: true),
            if (waiting) const TypingIndicator(),
          ],
        );
      },
    );
  }

  Widget _inputBar(ColorScheme scheme) {
    if (_recording) {
      return SafeArea(
        child: Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(28)),
          child: Row(children: [
            Icon(Icons.fiber_manual_record, color: scheme.error),
            const SizedBox(width: 8),
            Text('Recording… ${_recorder.elapsedSeconds}s / ${_recorder.maxSeconds}s'),
            const Spacer(),
            IconButton(tooltip: 'Cancel', icon: const Icon(Icons.delete_outline), onPressed: _cancelRecording),
            IconButton.filled(tooltip: 'Send voice note', icon: const Icon(Icons.send), onPressed: _toggleRecording),
          ]),
        ),
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _text,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendText(),
              decoration: const InputDecoration(hintText: 'Type in English, हिंदी or मराठी…'),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(tooltip: 'Voice note', icon: const Icon(Icons.mic), onPressed: _toggleRecording),
          const SizedBox(width: 4),
          IconButton.filled(
            tooltip: 'Send',
            icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            onPressed: _sending ? null : () => _sendText(),
          ),
        ]),
      ),
    );
  }
}
