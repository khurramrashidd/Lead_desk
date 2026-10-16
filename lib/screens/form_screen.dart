import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data/institute.dart';
import '../services/repo.dart';
import '../utils/responsive.dart';
import '../widgets/brand.dart';
import '../widgets/site_widgets.dart';
import 'chat/prospect_chat_screen.dart';

/// The website enquiry form. Submitting does not drop the person into a queue —
/// it opens a counselling conversation straight away, which is the point of PS3.
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

  List<String> get _courses => ['Not sure yet', ...Institute.courses.map((c) => c['name'] as String)];

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
        text: 'Website enquiry from ${_name.text.trim()}. Interested in: $_course.'
            '${q.isEmpty ? '' : ' Question: $q'}',
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ProspectChatScreen(source: widget.source, leadId: id)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send: $e')));
      }
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
    final phone = screenSizeOf(context) == ScreenSize.phone;
    return Scaffold(
      backgroundColor: context.scheme.surfaceContainerLow,
      appBar: AppBar(
        backgroundColor: context.scheme.surface,
        title: InstituteLogo(size: phone ? 28 : 32, compact: phone),
      ),
      body: SingleChildScrollView(
        child: MaxWidth(
          width: 560,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 40),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Eyebrow('Enquiry', icon: Icons.edit_note_rounded),
                  const SizedBox(height: 14),
                  Text('Tell us a little about you', style: context.texts.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Our counsellor replies in seconds — any time of day, in English, हिंदी or मराठी.',
                    style: context.texts.bodyLarge?.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 26),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: context.scheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.r20),
                      border: Border.all(color: context.scheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Full name *',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) => (v ?? '').trim().length < 2 ? 'Please enter your name' : null,
                        ),
                        const SizedBox(height: 14),
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
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email (optional)',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text('Course of interest', style: context.texts.titleSmall),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final c in _courses)
                            ChoiceChip(
                              label: Text(c),
                              selected: _course == c,
                              onSelected: (_) => setState(() => _course = c),
                              showCheckmark: false,
                              selectedColor: AppTheme.indigo.withValues(alpha: 0.14),
                              labelStyle: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: _course == c ? AppTheme.indigo : context.scheme.onSurfaceVariant,
                              ),
                              side: BorderSide(
                                color: _course == c ? AppTheme.indigo.withValues(alpha: 0.5) : context.scheme.outlineVariant,
                              ),
                            ),
                        ]),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _question,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Your question (optional)',
                            hintText: 'e.g. I have a 2-year gap — is that a problem?',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                          icon: _saving
                              ? const SizedBox(
                                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send_rounded, size: 18),
                          label: const Text('Submit and chat with a counsellor'),
                          onPressed: _saving ? null : _submit,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.lock_outline, size: 13, color: context.scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('Your details go only to our admissions team.',
                          style: context.texts.bodySmall?.copyWith(fontSize: 12)),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
