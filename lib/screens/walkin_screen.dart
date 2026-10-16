import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/institute.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/repo.dart';
import '../utils/ist.dart';
import '../utils/responsive.dart';

/// Front desk: add a visitor in fifteen seconds. Location and IST time are
/// captured automatically so the reports can compare walk-ins with other sources.
class WalkInScreen extends StatefulWidget {
  const WalkInScreen({super.key});

  @override
  State<WalkInScreen> createState() => _WalkInScreenState();
}

class _WalkInScreenState extends State<WalkInScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  String _course = 'Not sure yet';
  PlaceInfo? _place;
  bool _locating = false;
  bool _saving = false;
  final _arrivedAt = DateTime.now();

  List<String> get _courses => ['Not sure yet', ...Institute.courses.map((c) => c['name'] as String)];

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      final p = await LocationService.current();
      if (mounted) setState(() => _place = p);
    } catch (_) {
      // location is optional — a walk-in is still a walk-in
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final me = AuthService.displayName;
    final where = _place?.label.isNotEmpty == true ? _place!.label : 'front desk';
    try {
      await Repo.createLead(
        source: 'walkin',
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        city: _place?.city,
        lat: _place?.lat,
        lng: _place?.lng,
        assignedTo: me,
        status: 'engaged',
        extra: {
          'score': 55,
          'temperature': 'warm',
          'courseInterest': _course,
          'summary': [
            'Walked in at $where, ${Ist.full(_arrivedAt)}.',
            'Interested in: $_course.',
            _notes.text.trim().isEmpty ? 'Met $me at the desk.' : _notes.text.trim(),
          ],
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Walk-in saved — it is on the desk now.')),
    );
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = screenSizeOf(context) == ScreenSize.phone;
    return Scaffold(
      backgroundColor: context.scheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('New walk-in'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(child: IstClock(compact: phone)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: MaxWidth(
          width: 560,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.human.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppTheme.r16),
                      border: Border.all(color: AppTheme.human.withValues(alpha: 0.26)),
                    ),
                    child: Row(children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: _locating
                            ? const CircularProgressIndicator(strokeWidth: 2.2)
                            : const Icon(Icons.location_on_rounded, color: AppTheme.human),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            _place?.label.isNotEmpty == true
                                ? _place!.label
                                : (_locating ? 'Finding location…' : 'Location not available'),
                            style: context.texts.titleSmall?.copyWith(fontSize: 14.5),
                          ),
                          const SizedBox(height: 2),
                          Text('Arrived ${Ist.full(_arrivedAt)}',
                              style: context.texts.bodySmall?.copyWith(fontSize: 12.5)),
                        ]),
                      ),
                      IconButton(
                        tooltip: 'Refresh location',
                        icon: const Icon(Icons.my_location_rounded, size: 20),
                        onPressed: _locate,
                      ),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: context.scheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.r20),
                      border: Border.all(color: context.scheme.outlineVariant),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        autofocus: true,
                        decoration: const InputDecoration(labelText: 'Name *', prefixIcon: Icon(Icons.person_outline)),
                        validator: (v) => (v ?? '').trim().length < 2 ? 'Enter the visitor\'s name' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Mobile *', prefixIcon: Icon(Icons.call_outlined)),
                        validator: (v) =>
                            (v ?? '').replaceAll(RegExp(r'\D'), '').length < 10 ? 'Enter a 10-digit mobile number' : null,
                      ),
                      const SizedBox(height: 20),
                      Text('Interested in', style: context.texts.titleSmall),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final c in _courses)
                          ChoiceChip(
                            label: Text(c),
                            selected: _course == c,
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _course = c),
                            selectedColor: AppTheme.human.withValues(alpha: 0.14),
                            labelStyle: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _course == c ? AppTheme.human : context.scheme.onSurfaceVariant,
                            ),
                          ),
                      ]),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _notes,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          hintText: 'Background, worries, who came along…',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: AppTheme.human,
                        ),
                        icon: _saving
                            ? const SizedBox(
                                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_rounded, size: 18),
                        label: const Text('Save walk-in'),
                        onPressed: _saving ? null : _save,
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
