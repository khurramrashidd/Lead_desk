import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/repo.dart';

/// Demo simulator: sends an enquiry into the system exactly as if it had arrived on WhatsApp,
/// Instagram, Telegram, a phone call or a Google Form — so judges can see cross-channel
/// identity merge without five phones. Simulated leads never message a real number.
Future<void> showSimulator(BuildContext context, {void Function(String leadId)? onOpen}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 620),
    builder: (_) => _SimulatorSheet(onOpen: onOpen),
  );
}

class _Preset {
  const _Preset(this.label, this.channel, this.name, this.phone, this.message, {this.relation, this.studentName});
  final String label;
  final String channel;
  final String name;
  final String phone;
  final String message;
  final String? relation;
  final String? studentName;
}

const _presets = [
  _Preset('1 · Rahul Patil fills the website form', 'form', 'Rahul Patil', '098765 43210', 'Interested in Full Stack Java, weekend batch'),
  _Preset('2 · राहुल पाटल writes on WhatsApp', 'whatsapp', 'राहुल पाटल', '+91 98765-43210', 'नमस्कार, मला जावा कोर्सबद्दल माहिती हवी आहे. फी किती आहे?'),
  _Preset('3 · His father calls (voicemail)', 'call', 'Suresh Patil', '9822012345', 'Calling about my son Rahul\'s admission', relation: 'parent', studentName: 'Rahul Patil'),
  _Preset('Commerce grad with a gap · Instagram', 'instagram', 'Sneha K', '', 'I\'m a commerce graduate with a two-year gap — can I really become a developer?'),
  _Preset('Bargainer · Telegram', 'telegram', 'Vikram', '9811100011', 'My friend got 30% off. Give me the same or I join elsewhere.'),
  _Preset('Google Form · Data Science', 'googleform', 'Ananya Rao', '9000090000', 'Course: Data Science · Background: B.Sc Maths · Preferred: weekends'),
];

class _SimulatorSheet extends StatefulWidget {
  const _SimulatorSheet({this.onOpen});
  final void Function(String leadId)? onOpen;

  @override
  State<_SimulatorSheet> createState() => _SimulatorSheetState();
}

class _SimulatorSheetState extends State<_SimulatorSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _msg = TextEditingController();
  String _channel = 'whatsapp';
  String? _relation;
  String? _studentName;
  bool _busy = false;
  String? _result;

  static const _channels = {
    'whatsapp': '🟢 WhatsApp',
    'instagram': '📸 Instagram DM',
    'telegram': '✈️ Telegram',
    'call': '📞 Phone call / voicemail',
    'googleform': '🧾 Google Form',
    'form': '📝 Website form',
    'walkin': '🚶 Walk-in',
  };

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _msg.dispose();
    super.dispose();
  }

  void _use(_Preset p) => setState(() {
        _channel = p.channel;
        _name.text = p.name;
        _phone.text = p.phone;
        _msg.text = p.message;
        _relation = p.relation;
        _studentName = p.studentName;
      });

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final r = await Repo.simulate(
        channel: _channel,
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        message: _msg.text.trim().isEmpty ? null : _msg.text.trim(),
        relation: _relation,
        studentName: _studentName,
      );
      final id = '${r['leadId']}';
      setState(() => _result = '✅ Arrived as lead $id. Asha is replying; watch the desk.');
      if (widget.onOpen != null && mounted) {
        Navigator.of(context).pop();
        widget.onOpen!(id);
      }
    } catch (e) {
      setState(() => _result = '❌ $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 0, 22, 22 + bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('Simulate an enquiry', style: context.texts.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Arrives exactly like a real message on that channel (identity merge, AI reply, scoring, follow-ups). '
            'Simulated leads are never messaged on a real phone. Run 1 → 2 → 3 to show one person, one timeline.',
            style: context.texts.bodySmall?.copyWith(fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in _presets) ActionChip(label: Text(p.label, style: const TextStyle(fontSize: 12)), onPressed: () => _use(p)),
          ]),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey(_channel),
            initialValue: _channel,
            decoration: const InputDecoration(labelText: 'Channel'),
            items: [for (final e in _channels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _channel = v ?? 'whatsapp'),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name (any script)'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone (any format)'))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: _msg, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Message (English / हिंदी / मराठी / mixed)')),
          if (_relation != null) ...[
            const SizedBox(height: 8),
            Text('Sent by: $_relation of ${_studentName ?? 'the student'}', style: context.texts.bodySmall),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _busy ? null : _send,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: AppTheme.coral),
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, size: 18),
            label: const Text('Send into the desk'),
          ),
          if (_result != null) ...[const SizedBox(height: 10), Text(_result!, style: const TextStyle(fontSize: 13))],
        ]),
      ),
    );
  }
}
