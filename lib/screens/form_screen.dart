import 'package:flutter/material.dart';

import '../services/repo.dart';
import '../utils/responsive.dart';
import 'chat/prospect_chat_screen.dart';

/// Website enquiry form. After submitting, the conversation continues in chat,
/// so a form lead gets a counselling reply in seconds instead of waiting for a call.
class FormScreen extends StatefulWidget {
  const FormScreen({super.key, required this.source});
  final String source;

  @override
  State<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<FormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _question = TextEditingController();
  String _course = 'Not sure yet';
  bool _saving = false;

  static const _courses = [
    'Not sure yet',
    'Python Foundations',
    'Full Stack Java Developer',
    'MERN Full Stack (JavaScript)',
    'Data Science & AI with Python',
    'DevOps & Cloud',
    'Software Testing (Manual + Selenium)',
  ];

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final id = await Repo.createLead(
        source: widget.source,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        extra: {'courseInterest': _course},
      );
      final q = _question.text.trim();
      await Repo.sendProspectMessage(
        id,
        text: 'Website enquiry from ${_name.text.trim()}. Interested in: $_course.${q.isEmpty ? '' : ' Question: $q'}',
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ProspectChatScreen(source: widget.source, leadId: id),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _question]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enquire · TechSummitTrainers')),
      body: MaxWidth(
        width: 560,
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('Tell us a little about you. Our counsellor replies in seconds, any time of day.'),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Full name *'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Please enter your name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Mobile number *', hintText: 'e.g. 98765 43210'),
                validator: (v) => (v ?? '').replaceAll(RegExp(r'\D'), '').length < 10 ? 'Enter a 10-digit mobile number' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email (optional)'),
              ),
              const SizedBox(height: 12),
              Text('Course of interest', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in _courses)
                  ChoiceChip(label: Text(c), selected: _course == c, onSelected: (_) => setState(() => _course = c)),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _question,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Your question (optional)'),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: const Text('Submit and chat with a counsellor'),
                onPressed: _saving ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
