import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_theme.dart';
import '../../l10n.dart';
import '../../services/repo.dart';
import '../../services/voice_recorder.dart';
import '../../utils/ist.dart';
import '../../utils/responsive.dart';
import '../../widgets/lang_switch.dart';
import '../../widgets/message_bubble.dart';
import '../site/book_call_sheet.dart';

/// What a student or parent sees — from the QR code, the website widget or a link.
/// No app, no login, no form. Text or a voice note in English, हिंदी or मराठी.
class ProspectChatScreen extends StatefulWidget {
  const ProspectChatScreen({
    super.key,
    required this.source,
    this.leadId,
    this.embedded = false,
    this.onClose,
    this.prefill,
  });

  /// Where this conversation came from: web, qr, instagram, form…
  final String source;
  final String? leadId;

  /// true when the chat is docked inside the website instead of being a page.
  final bool embedded;
  final VoidCallback? onClose;

  /// Text placed in the box when the chat opens (e.g. "Is this right for me? — Full Stack Java").
  final String? prefill;

  @override
  State<ProspectChatScreen> createState() => _ProspectChatScreenState();
}

class _ProspectChatScreenState extends State<ProspectChatScreen> {
  static const _prefsKey = 'prospect_lead_id';

  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = VoiceRecorder();
  final _focus = FocusNode();

  String? _leadId;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _messageStream;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _leadSub;
  Timer? _recTimer;
  bool _recording = false;
  bool _sending = false;

  String get _greeting => tr('chat.greeting');

  List<String> get _starters => [tr('chat.s1'), tr('chat.s2'), tr('chat.s3'), tr('chat.s4')];

  @override
  void initState() {
    super.initState();
    if (widget.prefill != null) _text.text = widget.prefill!;
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final id = widget.leadId ?? prefs.getString(_prefsKey);
    if (id != null) {
      await prefs.setString(_prefsKey, id);
      _follow(id);
    }
  }

  /// Keep following this conversation even after the server merges it into an
  /// older lead for the same person (same phone / same name in another script).
  void _follow(String id) {
    if (!mounted) return;
    _leadSub?.cancel();
    setState(() {
      _leadId = id;
      _messageStream = Repo.watchMessages(id);
    });
    _leadSub = Repo.watchLead(id).listen(
      (snap) async {
        final mergedInto = snap.data()?['mergedInto'] as String?;
        if (mergedInto != null && mergedInto != _leadId) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefsKey, mergedInto);
          _follow(mergedInto);
        }
      },
      onError: (Object e) async {
        // Old or foreign conversation (for example a new anonymous session): start fresh.
        debugPrint('chat lead not readable, starting a new conversation: $e');
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefsKey);
        _leadSub?.cancel();
        if (mounted) {
          setState(() {
            _leadId = null;
            _messageStream = null;
          });
        }
      },
    );
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
    final body = (preset ?? _text.text).trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final id = await _ensureLead();
      _text.clear();
      await Repo.sendProspectMessage(id, text: body, channel: widget.source == 'qr' ? 'web' : 'web');
      _focus.requestFocus();
    } catch (e) {
      _snack(tr('chat.failed'));
      debugPrint('send failed: $e');
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
        _snack('${tr('chat.short')} (max ${_recorder.maxSeconds}s)');
        return;
      }
      final id = await _ensureLead();
      await Repo.sendProspectMessage(
        id,
        audioB64: note.base64,
        audioMime: note.mime,
        text: '🎤 Voice note (${note.seconds}s)',
      );
      return;
    }
    final ok = await _recorder.start();
    if (!ok) {
      _snack(tr('chat.mic'));
      return;
    }
    setState(() => _recording = true);
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    _leadSub?.cancel();
    _recorder.dispose();
    _text.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLang>(
      valueListenable: L10n.lang,
      builder: (context, _, _) => _buildChat(context),
    );
  }

  Widget _buildChat(BuildContext context) {
    final body = Column(
      children: [
        _header(context),
        Expanded(
          child: Container(
            color: context.isDark ? const Color(0xFF0A0F1A) : const Color(0xFFF3F6F7),
            child: _leadId == null ? _welcome() : _thread(),
          ),
        ),
        _composer(context),
      ],
    );

    if (widget.embedded) {
      return Material(color: context.scheme.surface, child: body);
    }
    return Scaffold(
      backgroundColor: context.scheme.surface,
      body: SafeArea(child: MaxWidth(width: 760, child: body)),
    );
  }

  // ----------------------------------------------------------------- header
  Widget _header(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(14, widget.embedded ? 12 : 10, 8, 12),
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: widget.embedded
            ? const BorderRadius.vertical(top: Radius.circular(AppTheme.r20))
            : BorderRadius.zero,
      ),
      child: Row(
        children: [
          if (!widget.embedded && Navigator.of(context).canPop())
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Text('अ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Asha', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16.5, letterSpacing: -0.2)),
                Row(children: [
                  _Dot(),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text('Admissions counsellor · 24×7',
                        overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white70, fontSize: 11.5)),
                  ),
                ]),
              ],
            ),
          ),
          const LangSwitch(onDark: true),
          IconButton(
            tooltip: tr('chat.human'),
            icon: const Icon(Icons.support_agent_rounded, color: Colors.white),
            onPressed: () => showBookCallSheet(context, source: widget.source),
          ),
          if (widget.onClose != null)
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- welcome
  Widget _welcome() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        children: [
          MessageBubble(role: 'ai', text: _greeting),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(tr('chat.try'),
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: context.scheme.onSurfaceVariant)),
          ),
          for (final s in _starters)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: context.scheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.r16),
                  child: InkWell(
                    onTap: () => _sendText(s),
                    borderRadius: BorderRadius.circular(AppTheme.r16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppTheme.r16),
                        border: Border.all(color: AppTheme.indigo.withValues(alpha: 0.28)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.north_east_rounded, size: 15, color: AppTheme.indigo),
                        const SizedBox(width: 9),
                        Flexible(child: Text(s, style: const TextStyle(fontSize: 13.5, height: 1.4))),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );

  // ----------------------------------------------------------------- thread
  Widget _thread() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _messageStream,
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final visible = docs
            .where((d) => d.data()['role'] != 'system' || d.data()['meta']?['kind'] == 'takeover')
            .toList();
        final last = visible.isEmpty ? null : visible.last.data();
        final lastAt = Ist.fromTimestamp(last?['createdAt']) ?? DateTime.now();
        final waiting = last != null && last['role'] == 'user' && DateTime.now().difference(lastAt).inSeconds < 90;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              _scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
            );
          }
        });

        return ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          children: [
            MessageBubble(role: 'ai', text: _greeting),
            for (final d in visible) MessageBubble.fromDoc(d.data(), prospectView: true),
            if (waiting) const TypingIndicator(),
            if (!waiting && last != null && last['role'] == 'ai') _quickReplies(last),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  /// A/B/C buttons under an aptitude question, so the answer is one tap.
  Widget _quickReplies(Map<String, dynamic> last) {
    final meta = (last['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (meta['kind'] != 'aptitude') return const SizedBox.shrink();
    final options = ((meta['options'] as List?) ?? const []).map((e) => '$e').toList();
    if (options.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('chat.pick'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in options)
            ActionChip(
              label: Text(o, style: const TextStyle(fontWeight: FontWeight.w600)),
              avatar: const Icon(Icons.touch_app_rounded, size: 16),
              onPressed: _sending ? null : () => _sendText(o.length > 1 ? o.substring(0, 1) : o),
            ),
        ]),
      ]),
    );
  }

  // --------------------------------------------------------------- composer
  Widget _composer(BuildContext context) {
    if (_recording) {
      final left = _recorder.maxSeconds - _recorder.elapsedSeconds;
      return Container(
        color: context.scheme.surface,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.hot.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppTheme.hot.withValues(alpha: 0.35)),
            ),
            child: Row(children: [
              const _Pulse(),
              const SizedBox(width: 10),
              Text('${_recorder.elapsedSeconds}s', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${tr('chat.listening')} $left ${tr('chat.left')}',
                    style: context.texts.bodySmall?.copyWith(fontSize: 12.5), overflow: TextOverflow.ellipsis),
              ),
              IconButton(tooltip: 'Cancel', icon: const Icon(Icons.delete_outline), onPressed: _cancelRecording),
              const SizedBox(width: 2),
              FilledButton(
                onPressed: _toggleRecording,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: const StadiumBorder(),
                ),
                child: Text(tr('chat.send')),
              ),
            ]),
          ),
        ),
      );
    }

    return Container(
      color: context.scheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendText(),
                    decoration: InputDecoration(
                      hintText: tr('chat.hint'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide(color: context.scheme.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: const BorderSide(color: AppTheme.indigo, width: 1.6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _RoundButton(
                  tooltip: 'Record a voice note',
                  icon: Icons.mic_none_rounded,
                  onTap: _toggleRecording,
                  filled: false,
                ),
                const SizedBox(width: 6),
                _RoundButton(
                  tooltip: 'Send',
                  icon: Icons.arrow_upward_rounded,
                  onTap: _sending ? null : () => _sendText(),
                  busy: _sending,
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 11, color: context.scheme.onSurfaceVariant),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '${tr('chat.privacy')} · AI Lead Desk',
                    style: TextStyle(fontSize: 10.8, color: context.scheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, this.tooltip, this.filled = true, this.busy = false});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool filled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: filled ? AppTheme.brandGradient : null,
        color: filled ? null : context.scheme.surfaceContainerHigh,
        shape: BoxShape.circle,
      ),
      child: busy
          ? const Padding(
              padding: EdgeInsets.all(14),
              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
            )
          : Icon(icon, color: filled ? Colors.white : context.scheme.onSurfaceVariant, size: 22),
    );
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: child),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(color: Color(0xFF34D399), shape: BoxShape.circle),
      );
}

class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.35, end: 1).animate(_c),
        child: const Icon(Icons.fiber_manual_record, color: AppTheme.hot, size: 14),
      );
}
