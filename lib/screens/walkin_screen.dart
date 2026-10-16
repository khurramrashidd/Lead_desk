import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/location_service.dart';
import '../services/repo.dart';
import '../utils/ist.dart';
import '../utils/responsive.dart';

/// Counsellor adds a visitor at the front desk. Location and IST time are captured automatically.
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

  static const _courses = ['Not sure yet', 'Python Foundations', 'Full Stack Java', 'MERN', 'Data Science', 'DevOps', 'Testing'];

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
      // location is optional
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    final me = prefs.getString('counsellor') ?? 'Priya';
    final where = _place?.label ?? 'front desk';
    try {
      await _create(me, where);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Walk-in saved. It now shows on the desk.')));
    Navigator.of(context).pop();
  }

  Future<void> _create(String me, String where) async {
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
          'Walk-in at $where, ${Ist.full(_arrivedAt)}.',
          'Interested in: $_course.',
          _notes.text.trim().isEmpty ? 'Met $me at the desk.' : _notes.text.trim(),
        ],
      },
    );
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New walk-in'), actions: const [Padding(padding: EdgeInsets.only(right: 12), child: Center(child: IstClock(compact: true)))]),
      body: MaxWidth(
        width: 560,
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: ListTile(
                  leading: _locating
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.location_on, color: scheme.primary),
                  title: Text(_place?.label.isNotEmpty == true ? _place!.label : (_locating ? 'Finding location…' : 'Location not available')),
                  subtitle: Text('Arrived ${Ist.full(_arrivedAt)}'),
                  trailing: IconButton(icon: const Icon(Icons.my_location), onPressed: _locate, tooltip: 'Refresh location'),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name *'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Enter the visitor\'s name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Mobile *'),
                validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 10 ? 'Enter a 10-digit mobile number' : null,
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in _courses)
                  ChoiceChip(label: Text(c), selected: _course == c, onSelected: (_) => setState(() => _course = c)),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Notes (background, worries, who came with them)'),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Save walk-in'),
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
