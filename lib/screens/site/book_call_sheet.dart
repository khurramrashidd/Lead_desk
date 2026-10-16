import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../data/institute.dart';
import '../../services/repo.dart';
import '../../utils/ist.dart';
import '../../utils/responsive.dart';
import '../../widgets/site_widgets.dart';

/// "I'd rather talk to a person." Takes the four things a counsellor needs —
/// name, phone, email and a one-line brief — and books a real slot for either a
/// phone call or a video meeting.
Future<void> showBookCallSheet(BuildContext context, {String source = 'web', String? leadName}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => BookCallSheet(source: source, leadName: leadName),
  );
}

class BookCallSheet extends StatefulWidget {
  const BookCallSheet({super.key, this.source = 'web', this.leadName});
  final String source;
  final String? leadName;

  @override
  State<BookCallSheet> createState() => _BookCallSheetState();
}

class _BookCallSheetState extends State<BookCallSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.leadName ?? '');
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _brief = TextEditingController();
  final _studentName = TextEditingController();

  String _kind = 'call';
  String _relation = 'self';
  String? _slotId;
  bool _saving = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _brief, _studentName]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Repo.requestCallback(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        brief: _brief.text.trim(),
        kind: _kind,
        source: widget.source,
        slotId: _slotId,
        relation: _relation,
        studentName: _relation == 'self' ? null : _studentName.text.trim(),
      );
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 4, 22, 22 + bottom),
      child: SingleChildScrollView(
        child: _done ? _success(context) : _formView(context),
      ),
    );
  }

  Widget _success(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppTheme.human.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: AppTheme.human, size: 32),
          ),
          const SizedBox(height: 18),
          Text(
            _slotId == null ? 'We will call you back' : 'Booked — see you then',
            style: context.texts.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            _slotId == null
                ? 'A counsellor will ring ${_phone.text.trim()} during ${Institute.policies['counselling'] == null ? 'working hours' : 'our calling hours'}. '
                    'Meanwhile Asha can answer anything straight away in the chat.'
                : 'You will get a reminder 24 hours and 1 hour before. '
                    '${_kind == 'meet' ? 'The video link is in the reminder.' : ''}',
            textAlign: TextAlign.center,
            style: context.texts.bodyMedium?.copyWith(fontSize: 14, height: 1.6),
          ),
          const SizedBox(height: 22),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
          const SizedBox(height: 8),
        ],
      );

  Widget _formView(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Eyebrow('Talk to a human', icon: Icons.support_agent_rounded),
          const SizedBox(height: 12),
          Text('Still deciding? Let a counsellor call you.', style: context.texts.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Tell us how to reach you and what you want to discuss. '
            '${Institute.policies['counselling'] ?? ''}',
            style: context.texts.bodyMedium?.copyWith(fontSize: 13.5),
          ),
          const SizedBox(height: 18),

          SegmentedButton<String>(
            style: SegmentedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
            segments: const [
              ButtonSegment(value: 'call', icon: Icon(Icons.call_outlined, size: 17), label: Text('Phone call')),
              ButtonSegment(value: 'meet', icon: Icon(Icons.videocam_outlined, size: 17), label: Text('Video meeting')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() {
              _kind = s.first;
              _slotId = null;
            }),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Your name *', prefixIcon: Icon(Icons.person_outline)),
            validator: (v) => (v ?? '').trim().length < 2 ? 'Please enter your name' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Mobile number *',
              hintText: '98765 43210',
              prefixIcon: Icon(Icons.call_outlined),
            ),
            validator: (v) =>
                (v ?? '').replaceAll(RegExp(r'\D'), '').length < 10 ? 'Enter a 10-digit mobile number' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email *', prefixIcon: Icon(Icons.mail_outline)),
            validator: (v) => (v ?? '').contains('@') ? null : 'We send the meeting details here',
          ),
          const SizedBox(height: 16),

          Text('Who is this for?', style: context.texts.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in const [
              ('self', 'Myself'),
              ('parent', 'My child'),
              ('sibling', 'My brother/sister'),
              ('friend', 'A friend'),
            ])
              ChoiceChip(
                label: Text(r.$2),
                selected: _relation == r.$1,
                showCheckmark: false,
                onSelected: (_) => setState(() => _relation = r.$1),
                selectedColor: AppTheme.indigo.withValues(alpha: 0.14),
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _relation == r.$1 ? AppTheme.indigo : context.scheme.onSurfaceVariant,
                ),
              ),
          ]),
          if (_relation != 'self') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _studentName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Student\'s name',
                prefixIcon: Icon(Icons.school_outlined),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _brief,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'What do you want to discuss? *',
              hintText: 'e.g. B.Com, 2-year gap — which course should I start with?',
              alignLabelWithHint: true,
            ),
            validator: (v) => (v ?? '').trim().length < 5 ? 'One line is enough' : null,
          ),

          const SizedBox(height: 18),
          Text('Pick a time (optional)', style: context.texts.titleSmall),
          const SizedBox(height: 2),
          Text('Leave it blank and we will call you in working hours.',
              style: context.texts.bodySmall?.copyWith(fontSize: 12)),
          const SizedBox(height: 10),
          _SlotPicker(
            kind: _kind,
            selected: _slotId,
            onSelect: (id) => setState(() => _slotId = _slotId == id ? null : id),
            compact: phone,
          ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.scheme.errorContainer,
                borderRadius: BorderRadius.circular(AppTheme.r12),
              ),
              child: Text(_error!, style: TextStyle(color: context.scheme.onErrorContainer, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(_kind == 'meet' ? Icons.videocam_rounded : Icons.call_rounded, size: 19),
            label: Text(_slotId == null
                ? (_kind == 'meet' ? 'Request a video meeting' : 'Request a callback')
                : 'Confirm this time'),
            onPressed: _saving ? null : _submit,
          ),
          const SizedBox(height: 10),
          Text(
            'Your details go only to our admissions team.',
            textAlign: TextAlign.center,
            style: context.texts.bodySmall?.copyWith(fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _SlotPicker extends StatelessWidget {
  const _SlotPicker({required this.kind, required this.selected, required this.onSelect, required this.compact});
  final String kind;
  final String? selected;
  final ValueChanged<String> onSelect;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: Repo.watchSlots(kind),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 44, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final docs = (snap.data ?? []).take(compact ? 6 : 8).toList();
        if (docs.isEmpty) {
          return Text(
            'No open times in the next few days — send the request and we will ring you.',
            style: context.texts.bodySmall?.copyWith(fontSize: 12.5),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in docs)
              _SlotChip(
                label: Ist.full(Ist.fromTimestamp(d.data()['startAt']) ?? DateTime.now()),
                seats: ((d.data()['capacity'] as num?)?.toInt() ?? 0) - ((d.data()['booked'] as num?)?.toInt() ?? 0),
                selected: selected == d.id,
                onTap: () => onSelect(d.id),
              ),
          ],
        );
      },
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({required this.label, required this.seats, required this.selected, required this.onTap});
  final String label;
  final int seats;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.indigo : context.scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppTheme.r12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.r12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.replaceAll(' IST', ''),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : context.scheme.onSurface,
                ),
              ),
              Text(
                seats <= 2 ? 'only $seats left' : '$seats seats',
                style: TextStyle(
                  fontSize: 10.5,
                  color: selected ? Colors.white70 : context.scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
