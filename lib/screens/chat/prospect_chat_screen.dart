import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_theme.dart';
import '../../l10n.dart';
import '../../services/repo.dart';
import '../../services/voice_recorder.dart';
import '../../utils/ist.dart';
import '../../utils/responsive.dart';
import '../../widgets/channel_links.dart';
import '../../widgets/lang_switch.dart';
import '../../widgets/message_bubble.dart';
import '../site/book_call_sheet.dart';

/// What a student or parent sees — from the QR code, the website widget or a link.
/// No app, no login, no form. Text or a voice note in English, हिंदी or मराठी.
///
/// The first questions (who is this for, the student's name and contact, the course list)
/// come from the server as tappable chips; then Asha counsels.
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

  /// Text placed in the box when the chat opens (e.g. "Tell me about Full Stack Java").
  final String? prefill;

  @override
  State<ProspectChatScreen> createState() => _ProspectChatScreenState();
}

class _ProspectChatScreenState extends State<ProspectChatScreen> {
  static const _prefsKey = 'prospect_lead_id';

  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = VoiceRecorder();
  final _player = AudioPlayer();
  final _focus = FocusNode();
  final _subs = <StreamSubscription<dynamic>>[];

  String? _leadId;
  Map<String, dynamic> _lead = const {};
  Stream<QuerySnapshot<Map<String, dynamic>>>? _messageStream;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _leadSub;
  Timer? _recTimer;
  Timer? _ticker;
  bool _recording = false;
  bool _sending = false;
  int _lastCount = 0;

  // Voice preview: recorded, not sent yet.
  VoiceNote? _pending;
  bool _playing = false;
  Duration _position = Duration.zero;

  String get _greeting => tr('chat.greeting');

  List<String> get _starters => [tr('chat.s1'), tr('chat.s2'), tr('chat.s4')];

  @override
  void initState() {
    super.initState();
    if (widget.prefill != null) _text.text = widget.prefill!;
    _subs.add(_player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    }));
    _subs.add(_player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    }));
    // Re-check "is Asha still typing?" every few seconds, even when nothing new arrives.
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _leadId != null) setState(() {});
    });
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
        final data = snap.data() ?? const <String, dynamic>{};
        if (mounted) setState(() => _lead = data);
        final mergedInto = data['mergedInto'] as String?;
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
            _lead = const {};
            _messageStream = null;
          });
        }
      },
    );
  }

  Future<String> _ensureLead() async {
    if (_leadId != null) return _leadId!;
    final id = await Repo.createLead(source: widget.source, extra: {'uiLang': L10n.lang.value.name});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, id);
    _follow(id);
    return id;
  }

  Future<void> _sendText([String? preset, String? choiceId]) async {
    final body = (preset ?? _text.text).trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final id = await _ensureLead();
      if (preset == null) _text.clear();
      await Repo.sendProspectMessage(
        id,
        text: body,
        channel: 'web',
        meta: {'uiLang': L10n.lang.value.name, 'choiceId': ?choiceId},
      );
      if (preset == null) _focus.requestFocus();
    } catch (e) {
      _snack(tr('chat.failed'));
      debugPrint('send failed: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ------------------------------------------------------------------ voice
  Future<void> _startRecording() async {
    await _discardPreview();
    final ok = await _recorder.start();
    if (!ok) {
      _snack(tr('chat.mic'));
      return;
    }
    setState(() => _recording = true);
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_recorder.elapsedSeconds >= _recorder.maxSeconds) _stopRecording();
    });
  }

  /// Stops recording and shows the preview (listen, then send or delete).
  Future<void> _stopRecording() async {
    _recTimer?.cancel();
    if (!_recording) return;
    setState(() => _recording = false);
    final note = await _recorder.stop();
    if (note == null) {
      _snack('${tr('chat.short')} (max ${_recorder.maxSeconds}s)');
      return;
    }
    setState(() {
      _pending = note;
      _position = Duration.zero;
    });
  }

  Future<void> _cancelRecording() async {
    _recTimer?.cancel();
    await _recorder.cancel();
    if (mounted) setState(() => _recording = false);
  }

  Future<void> _togglePlay() async {
    final note = _pending;
    if (note == null) return;
    try {
      if (_playing) {
        await _player.pause();
      } else if (_player.state == PlayerState.paused) {
        await _player.resume();
      } else {
        await _player.play(BytesSource(note.bytes, mimeType: note.mime));
      }
    } catch (e) {
      debugPrint('preview playback failed: $e');
      _snack('Could not play the preview on this device. You can still send it.');
    }
  }

  Future<void> _discardPreview() async {
    if (_pending == null) return;
    try {
      await _player.stop();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _pending = null;
        _playing = false;
        _position = Duration.zero;
      });
    }
  }

  Future<void> _sendVoice() async {
    final note = _pending;
    if (note == null || _sending) return;
    setState(() => _sending = true);
    try {
      try {
        await _player.stop();
      } catch (_) {}
      final id = await _ensureLead();
      await Repo.sendProspectMessage(
        id,
        audioB64: note.base64,
        audioMime: note.mime,
        text: '🎤 Voice note (${note.seconds}s)',
        meta: {'uiLang': L10n.lang.value.name},
      );
      if (mounted) {
        setState(() {
          _pending = null;
          _playing = false;
          _position = Duration.zero;
        });
      }
    } catch (e) {
      _snack(tr('chat.failed'));
      debugPrint('voice send failed: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    _ticker?.cancel();
    _leadSub?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
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
      padding: EdgeInsets.fromLTRB(widget.embedded ? 14 : 4, 10, 4, 10),
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: widget.embedded ? const BorderRadius.vertical(top: Radius.circular(AppTheme.r20)) : BorderRadius.zero,
      ),
      child: Row(
        children: [
          if (!widget.embedded && Navigator.of(context).canPop())
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Text('अ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Asha', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16.5, letterSpacing: -0.2)),
                Row(children: [
                  const _Dot(),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(tr('chat.status'), overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                  ),
                ]),
              ],
            ),
          ),
          const LangMenuButton(),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            position: PopupMenuPosition.under,
            onSelected: (v) {
              switch (v) {
                case 'human':
                  showBookCallSheet(context, source: widget.source);
                case 'wa':
                  openChannel(context, ChatChannel.whatsapp);
                case 'tg':
                  openChannel(context, ChatChannel.telegram);
                case 'form':
                  openChannel(context, ChatChannel.form);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'human', child: _menuRow(Icons.support_agent_rounded, tr('chat.human'), AppTheme.human)),
              PopupMenuItem(value: 'wa', child: _menuRow(ChatChannel.whatsapp.icon, tr('talk.whatsapp'), ChannelColors.whatsapp)),
              PopupMenuItem(value: 'tg', child: _menuRow(ChatChannel.telegram.icon, tr('talk.telegram'), ChannelColors.telegram)),
              PopupMenuItem(value: 'form', child: _menuRow(ChatChannel.form.icon, tr('qr.formOpen'), ChannelColors.form)),
            ],
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

  Widget _menuRow(IconData icon, String label, Color color) => Row(children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 12),
        Flexible(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
      ]);

  // ---------------------------------------------------------------- welcome
  Widget _welcome() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        children: [
          MessageBubble(role: 'ai', text: '$_greeting\n\n${tr('chat.who')}'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in const ['self', 'parent', 'friend'])
              ActionChip(
                avatar: Icon(
                  switch (r) {
                    'self' => Icons.school_rounded,
                    'parent' => Icons.family_restroom_rounded,
                    _ => Icons.people_alt_rounded,
                  },
                  size: 17,
                  color: AppTheme.indigo,
                ),
                label: Text(tr('chat.rel.$r'), style: const TextStyle(fontWeight: FontWeight.w700)),
                onPressed: _sending ? null : () => _sendText(tr('chat.rel.$r'), 'rel:$r'),
              ),
          ]),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(tr('chat.orAsk'),
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: context.scheme.onSurfaceVariant)),
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
          const SizedBox(height: 12),
          const Row(children: [
            Expanded(child: TalkButton(ChatChannel.whatsapp, compact: true)),
            SizedBox(width: 8),
            Expanded(child: TalkButton(ChatChannel.telegram, compact: true)),
          ]),
        ],
      );

  // ----------------------------------------------------------------- thread
  Widget _thread() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _messageStream,
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final visible = docs.where((d) => d.data()['role'] != 'system' || d.data()['meta']?['kind'] == 'takeover').toList();
        final last = visible.isEmpty ? null : visible.last.data();
        final lastAt = Ist.fromTimestamp(last?['createdAt']) ?? DateTime.now();
        final waitingSecs = last != null && last['role'] == 'user' ? DateTime.now().difference(lastAt).inSeconds : -1;
        final ai = (_lead['ai'] as Map?)?.cast<String, dynamic>() ?? const {};
        final humanMode = _lead['aiPaused'] == true;

        if (visible.length != _lastCount) {
          _lastCount = visible.length;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) {
              _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
            }
          });
        }

        return ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          children: [
            MessageBubble(role: 'ai', text: _greeting),
            for (final d in visible) MessageBubble.fromDoc(d.data(), prospectView: true),
            if (waitingSecs >= 0) _waiting(waitingSecs, ai, humanMode),
            if (waitingSecs < 0 && last != null && last['role'] == 'ai') _quickReplies(last),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  /// Never an endless "typing…": after a while, say what is happening and offer other ways.
  Widget _waiting(int secs, Map<String, dynamic> ai, bool humanMode) {
    if (humanMode) {
      return _Note(icon: Icons.support_agent_rounded, text: tr('chat.humanWait'));
    }
    if (secs < 25 && ai['retryAt'] == null) return const TypingIndicator();
    if (secs < 75 && ai['retryAt'] == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const TypingIndicator(),
        Padding(
          padding: const EdgeInsets.only(left: 6, top: 2),
          child: Text(tr('chat.slow'), style: context.texts.bodySmall?.copyWith(fontSize: 12)),
        ),
      ]);
    }
    return _Note(
      icon: Icons.schedule_rounded,
      text: tr('chat.retrying'),
      actions: [
        const TalkButton(ChatChannel.whatsapp, compact: true),
        const TalkButton(ChatChannel.telegram, compact: true),
        OutlinedButton.icon(
          onPressed: () => showBookCallSheet(context, source: widget.source),
          icon: const Icon(Icons.support_agent_rounded, size: 16),
          label: Text(tr('chat.human')),
        ),
      ],
    );
  }

  /// One-tap answers: intake questions (who / course / skip) and aptitude A/B/C.
  Widget _quickReplies(Map<String, dynamic> last) {
    final meta = (last['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
    final options = ((meta['options'] as List?) ?? const []).map((e) => '$e').toList();
    if (options.isEmpty) return const SizedBox.shrink();
    final choices = ((meta['choices'] as List?) ?? const []).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
    final aptitude = meta['kind'] == 'aptitude';
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(aptitude ? 'chat.pick' : 'chat.pickOne'),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.scheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < options.length; i++)
            ActionChip(
              label: Text(options[i], style: const TextStyle(fontWeight: FontWeight.w600)),
              avatar: Icon(aptitude ? Icons.touch_app_rounded : Icons.chevron_right_rounded, size: 16),
              onPressed: _sending
                  ? null
                  : () => aptitude
                      ? _sendText(options[i].length > 1 ? options[i].substring(0, 1) : options[i])
                      : _sendText(options[i], i < choices.length ? '${choices[i]['id']}' : null),
            ),
        ]),
      ]),
    );
  }

  // --------------------------------------------------------------- composer
  Widget _composer(BuildContext context) {
    if (_recording) return _recordingBar(context);
    if (_pending != null) return _previewBar(context, _pending!);

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
                _RoundButton(tooltip: 'Record a voice note', icon: Icons.mic_none_rounded, onTap: _startRecording, filled: false),
                const SizedBox(width: 6),
                _RoundButton(tooltip: 'Send', icon: Icons.arrow_upward_rounded, onTap: _sending ? null : () => _sendText(), busy: _sending),
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

  Widget _recordingBar(BuildContext context) {
    final left = _recorder.maxSeconds - _recorder.elapsedSeconds;
    return Container(
      color: context.scheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.hot.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.hot.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            const _Pulse(),
            const SizedBox(width: 8),
            Text('${_recorder.elapsedSeconds}s', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${tr('chat.listening')} $left ${tr('chat.left')}',
                  style: context.texts.bodySmall?.copyWith(fontSize: 12.5), overflow: TextOverflow.ellipsis),
            ),
            IconButton(tooltip: tr('chat.cancel'), icon: const Icon(Icons.delete_outline), onPressed: _cancelRecording),
            FilledButton.icon(
              onPressed: _stopRecording,
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: Text(tr('voice.stop')),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.hot,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: const StadiumBorder(),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Listen to the note, then send it or throw it away.
  Widget _previewBar(BuildContext context, VoiceNote note) {
    final total = note.seconds;
    final pos = _position.inSeconds.clamp(0, total).toInt();
    String mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    return Container(
      color: context.scheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 6),
            child: Text(tr('voice.preview'), style: context.texts.bodySmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.indigo.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppTheme.indigo.withValues(alpha: 0.30)),
            ),
            child: Row(children: [
              IconButton(tooltip: tr('voice.delete'), icon: const Icon(Icons.delete_outline_rounded), onPressed: _sending ? null : _discardPreview),
              IconButton.filledTonal(
                tooltip: _playing ? tr('voice.pause') : tr('voice.play'),
                icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                onPressed: _togglePlay,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0.0 : (_position.inMilliseconds / (total * 1000)).clamp(0.0, 1.0).toDouble(),
                      minHeight: 5,
                      backgroundColor: AppTheme.indigo.withValues(alpha: 0.15),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${mmss(pos)} / ${mmss(total)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _sending ? null : _sendVoice,
                icon: _sending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 17),
                label: Text(tr('chat.send')),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: const StadiumBorder()),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.actions = const []});
  final IconData icon;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.scheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.r16),
          border: Border.all(color: context.scheme.outlineVariant),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: AppTheme.indigo),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.45))),
          ]),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ]),
      );
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
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

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
