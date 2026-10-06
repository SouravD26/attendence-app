import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../data/leave_models.dart';
import '../state/leave_state.dart';
import 'leave_screen.dart' show formatDays;

/// Full-screen "Apply for leave", carrying the same fields as the web form in
/// attendance.php: leave type, from, to (blank means a single day) and reason.
///
/// Returns true once the request is accepted.
Future<bool?> showLeaveApplyScreen(
  BuildContext context, {
  required LeaveState state,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => LeaveApplyScreen(state: state),
    ),
  );
}

class LeaveApplyScreen extends StatefulWidget {
  const LeaveApplyScreen({super.key, required this.state});

  final LeaveState state;

  @override
  State<LeaveApplyScreen> createState() => _LeaveApplyScreenState();
}

class _LeaveApplyScreenState extends State<LeaveApplyScreen> {
  static final _display = DateFormat('EEE, d MMM yyyy');

  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  LeaveType? _type;
  DateTime? _start;

  /// Optional, exactly as on the web: blank means a one-day leave.
  DateTime? _end;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// Whole days, inclusive of both ends.
  double get _days {
    if (_start == null) return 0;
    final end = _end ?? _start!;
    return end.difference(_start!).inDays + 1.0;
  }

  /// The remaining balance for the chosen type, when the server tracks one.
  LeaveBalance? get _balance {
    final type = _type;
    if (type == null) return null;
    for (final b in widget.state.balance) {
      if (b.code == type.code || b.name == type.name) return b;
    }
    return null;
  }

  Future<void> _pick({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_start ?? now) : (_end ?? _start ?? now),
      // A year either side covers back-dated requests and advance planning.
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;

    setState(() {
      if (isStart) {
        _start = picked;
        // Keep the range valid rather than making the user fix it.
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
        if (_start == null || _start!.isAfter(picked)) _start = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_type == null) return _toast('Choose a leave type.');
    if (_start == null) return _toast('Choose the date your leave starts.');

    setState(() => _busy = true);
    final error = await widget.state.apply(
      leaveType: _type!.code,
      start: _start!,
      // Blank "to" means a single day, matching the web form.
      end: _end ?? _start!,
      reason: _reason.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (error != null) return _toast(error);
    Navigator.pop(context, true);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final types = widget.state.types;
    final balance = _balance;

    return Scaffold(
      appBar: AppBar(title: const Text('Apply for leave')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.gutter,
            8,
            AppTheme.gutter,
            16,
          ),
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Send request'),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.gutter,
            8,
            AppTheme.gutter,
            24,
          ),
          children: [
            const _FieldLabel('Leave type'),
            if (types.isEmpty)
              Text(
                'Leave types are still loading. Go back and pull to refresh.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              )
            else
              DropdownButtonFormField<LeaveType>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(hintText: 'Leave type…'),
                items: [
                  for (final t in types)
                    DropdownMenuItem(
                      value: t,
                      child: Text(t.name.isEmpty ? t.code : t.name),
                    ),
                ],
                onChanged: (v) => setState(() => _type = v),
              ),

            // Only meaningful once HR has configured an allowance.
            if (balance != null && balance.allowed > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet_outlined,
                        size: 17, color: scheme.primary),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '${formatDays(balance.balance)} of '
                        '${formatDays(balance.allowed)} days left this year',
                        style: TextStyle(fontSize: 12.5, color: scheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),

            const _FieldLabel('From'),
            _DateField(
              value: _start == null ? null : _display.format(_start!),
              hint: 'Select the first day',
              onTap: () => _pick(isStart: true),
              onClear: null,
            ),
            const SizedBox(height: 18),

            const _FieldLabel('To', optional: 'leave blank for one day'),
            _DateField(
              value: _end == null ? null : _display.format(_end!),
              hint: 'Same as the From date',
              onTap: () => _pick(isStart: false),
              onClear: _end == null ? null : () => setState(() => _end = null),
            ),

            if (_days > 0) ...[
              const SizedBox(height: 12),
              Text(
                '${formatDays(_days)} ${_days == 1 ? 'day' : 'days'} '
                'will be requested.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 18),

            const _FieldLabel('Reason'),
            TextFormField(
              controller: _reason,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Reason',
                alignLabelWithHint: true,
              ),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? 'Tell your approver why.'
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.optional});

  final String text;
  final String? optional;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (optional != null) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '($optional)',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.hint,
    required this.onTap,
    required this.onClear,
  });

  final String? value;
  final String hint;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: InputDecoration(
          suffixIcon: onClear == null
              ? const Icon(Icons.calendar_today_rounded, size: 18)
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: onClear,
                  tooltip: 'Clear',
                ),
        ),
        child: Text(
          value ?? hint,
          style: TextStyle(
            fontSize: 14,
            color: value == null ? scheme.onSurfaceVariant : null,
          ),
        ),
      ),
    );
  }
}
