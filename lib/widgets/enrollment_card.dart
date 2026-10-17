import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../screens/auth/auth_gate.dart';
import '../services/repo.dart';
import '../utils/ist.dart';
import 'lead_widgets.dart';

/// Enrolment of one lead: UPI registration fee, the receipt photo the student sent, and
/// (admin only) "Verify & allot course" / "Not verified". Used on the desk and the master dashboard.
class EnrollmentCard extends StatefulWidget {
  const EnrollmentCard({super.key, required this.leadId, required this.enrollment});
  final String leadId;
  final Map<String, dynamic> enrollment;

  static String statusLabel(String s) => switch (s) {
        'form' => 'Filling the enrolment form',
        'confirm' => 'Reviewing details',
        'otp' => 'Verifying email code',
        'cancelled' => 'Form cancelled',
        'choosing_course' => 'Choosing a course',
        'awaiting_details' => 'Wants to pay: no UPI ID set',
        'awaiting_receipt' => 'QR sent, waiting for receipt',
        'receipt_received' => 'Receipt received: verify',
        'verified' => 'Verified · enrolled',
        'rejected' => 'Not verified',
        _ => s,
      };

  static Color statusColor(String s) => switch (s) {
        'receipt_received' => AppTheme.hot,
        'verified' => AppTheme.success,
        'rejected' => AppTheme.coral,
        _ => AppTheme.info,
      };

  @override
  State<EnrollmentCard> createState() => _EnrollmentCardState();
}

class _EnrollmentCardState extends State<EnrollmentCard> {
  Future<Map<String, dynamic>?>? _receipt;
  List<Map<String, dynamic>> _courses = const [];
  String? _courseId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(EnrollmentCard old) {
    super.didUpdateWidget(old);
    if (old.enrollment['receiptMsgId'] != widget.enrollment['receiptMsgId']) _load();
  }

  void _load() {
    final rid = widget.enrollment['receiptMsgId'] as String?;
    _receipt = rid == null ? null : Repo.message(widget.leadId, rid);
    final form = (widget.enrollment['form'] as Map?)?.cast<String, dynamic>() ?? const {};
    _courseId ??= (form['courseId'] ?? widget.enrollment['courseId']) as String?;
    Repo.db.doc('kb/main').get().then((s) {
      final list = ((s.data()?['courses'] as List?) ?? const []).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
      if (mounted) setState(() => _courses = list);
    });
  }

  Future<void> _resend() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      messenger.showSnackBar(SnackBar(content: Text(await Repo.resendConfirmation(leadId: widget.leadId))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('❌ $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(bool approve) async {
    final messenger = ScaffoldMessenger.of(context);
    String? note;
    if (!approve) {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Payment not verified'),
          content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Reason (for the desk, optional)')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Mark not verified')),
          ],
        ),
      );
      if (ok != true) return;
      note = c.text.trim().isEmpty ? null : c.text.trim();
    }
    setState(() => _busy = true);
    try {
      final r = await Repo.verifyEnrollment(widget.leadId, approve: approve, courseId: _courseId, note: note);
      if (approve && mounted) setState(() => _verifiedHere = true);
      messenger.showSnackBar(SnackBar(content: Text('✅ $r')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('❌ $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _verifiedHere = false;

  /// Live: the card follows the lead, so "Verified" shows the moment it is saved.
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Repo.watchLead(widget.leadId),
      builder: (context, snap) {
        final live = (snap.data?.data()?['enrollment'] as Map?)?.cast<String, dynamic>();
        return _body(context, live ?? widget.enrollment);
      },
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic> e) {
    final status = _verifiedHere && e['status'] != 'verified' ? 'verified' : '${e['status'] ?? ''}';
    final admin = StaffScope.isAdmin(context);
    final at = Ist.fromTimestamp(e['receiptAt']) ?? Ist.fromTimestamp(e['startedAt']);
    final verified = status == 'verified';
    final canDecide = admin && !verified && (status == 'receipt_received' || status == 'rejected' || status == 'awaiting_receipt');
    final form = (e['form'] as Map?)?.cast<String, dynamic>() ?? const {};
    const fields = [
      ('name', 'Name'),
      ('phone', 'Mobile'),
      ('whatsapp', 'WhatsApp'),
      ('email', 'Email'),
      ('dob', 'Date of birth'),
      ('city', 'City'),
      ('qualification', 'Qualification'),
      ('address', 'Address'),
      ('guardianName', 'Parent / guardian'),
      ('guardianPhone', "Parent's mobile"),
      ('course', 'Course (student\'s choice)'),
      ('mode', 'Mode'),
      ('batch', 'Batch'),
      ('start', 'Start'),
    ];
    return InsightCard(
      title: 'Enrolment & payment',
      icon: Icons.currency_rupee_rounded,
      accent: EnrollmentCard.statusColor(status),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Chip(
            label: Text(EnrollmentCard.statusLabel(status), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            backgroundColor: EnrollmentCard.statusColor(status).withValues(alpha: 0.12),
            side: BorderSide.none,
            visualDensity: VisualDensity.compact,
          ),
          if (e['amount'] != null) Text('₹${e['amount']}', style: const TextStyle(fontWeight: FontWeight.w800)),
          if (e['courseName'] != null) Text('${e['courseName']}', style: const TextStyle(fontSize: 13)),
          if (at != null) Text(Ist.full(at), style: TextStyle(fontSize: 12, color: context.scheme.onSurfaceVariant)),
        ]),
        if (verified)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.success.withValues(alpha: 0.5)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('✅ Verified · course allotted', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.success, fontSize: 14)),
              const SizedBox(height: 4),
              if (e['admissionId'] != null) SelectableText('🆔 Admission ID: ${e['admissionId']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              if (e['courseName'] != null) Text('🎓 ${e['courseName']}', style: const TextStyle(fontSize: 13)),
              if (Ist.fromTimestamp(e['confirmationSentAt']) != null)
                Text(
                  'Confirmation sent ${Ist.full(Ist.fromTimestamp(e['confirmationSentAt'])!)}'
                  '${(e['confirmationSentTo'] as List?)?.isNotEmpty == true ? ' to ${(e['confirmationSentTo'] as List).join(', ')}' : ''}',
                  style: TextStyle(fontSize: 12, color: context.scheme.onSurfaceVariant),
                ),
              if (admin) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _resend,
                  icon: const Icon(Icons.send_rounded, size: 17),
                  label: const Text('Resend confirmation'),
                ),
              ],
            ]),
          ),
        if (form.isNotEmpty) ...[
          const SizedBox(height: 10),
          Table(
            columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            children: [
              for (final f in fields)
                if (form[f.$1] != null)
                  TableRow(children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 12, bottom: 4),
                      child: Text(f.$2, style: TextStyle(fontSize: 12.5, color: context.scheme.onSurfaceVariant)),
                    ),
                    Padding(padding: const EdgeInsets.only(bottom: 4), child: SelectableText('${form[f.$1]}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                  ]),
            ],
          ),
          Text(
            e['emailVerified'] == true ? '✅ Email verified with a code' : '⚠️ Email not verified${e['note'] != null ? ' (${e['note']})' : ''}',
            style: TextStyle(fontSize: 12, color: e['emailVerified'] == true ? AppTheme.success : context.scheme.onSurfaceVariant),
          ),
        ],
        if (e['verifiedBy'] != null) ...[
          const SizedBox(height: 4),
          Text('Decided by ${e['verifiedBy']}${e['note'] != null ? ' · ${e['note']}' : ''}', style: TextStyle(fontSize: 12, color: context.scheme.onSurfaceVariant)),
        ],
        if (_receipt != null)
          FutureBuilder<Map<String, dynamic>?>(
            future: _receipt,
            builder: (context, snap) {
              final b64 = snap.data?['imageB64'] as String?;
              if (b64 == null) return const SizedBox.shrink();
              final bytes = base64Decode(b64);
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: InkWell(
                  onTap: () => showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.memory(bytes)))),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 260), child: Image.memory(bytes, fit: BoxFit.contain)),
                  ),
                ),
              );
            },
          ),
        if (canDecide) ...[
          const SizedBox(height: 12),
          if (_courses.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _courses.any((c) => c['id'] == _courseId) ? _courseId : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Allot course (student\'s choice is pre-selected)', isDense: true),
              items: [
                for (final c in _courses)
                  DropdownMenuItem(
                    value: '${c['id']}',
                    child: Text('${c['name']}${c['id'] == form['courseId'] ? '  ★ student\'s choice' : ''}', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _courseId = v),
            ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: _busy ? null : () => _decide(true),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
              icon: const Icon(Icons.verified_rounded, size: 18),
              label: const Text('Verify, allot & create admission ID'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _decide(false),
              icon: const Icon(Icons.block_rounded, size: 18),
              label: const Text('Not verified'),
            ),
          ]),
        ] else if (!admin && status == 'receipt_received')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('An admin verifies the payment and allots the course.', style: TextStyle(fontSize: 12, color: context.scheme.onSurfaceVariant)),
          ),
      ]),
    );
  }
}
