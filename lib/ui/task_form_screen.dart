import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/task_form_models.dart';
import '../state/task_form_state.dart';

/// Opens the department's "Daily Task Form". Returns true once submitted.
Future<bool?> showTaskFormScreen(
  BuildContext context, {
  required TaskFormState state,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TaskFormScreen(state: state),
    ),
  );
}

/// Built entirely from the `fields` the server sends — each department's
/// Google Form asks different questions, so nothing here is hardcoded.
class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({super.key, required this.state});

  final TaskFormState state;

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();

  /// text / textarea / email / date / time — dates and times are kept as the
  /// wire strings (YYYY-MM-DD, HH:MM) so submitting is a straight copy.
  final Map<String, TextEditingController> _text = {};
  final Map<String, String?> _radio = {};
  final Map<String, Set<String>> _checks = {};

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onState);
    _seed();
    // Refetch so the prefilled date and the month in the title are current.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.state.load();
      if (mounted) setState(_seed);
    });
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  /// Fills inputs from the server's prefill without overwriting anything the
  /// user has already typed or picked.
  void _seed() {
    for (final f in widget.state.form?.fields ?? const <TaskFormField>[]) {
      switch (f.type) {
        case TaskFieldType.radio:
          _radio.putIfAbsent(f.key, () {
            final v = f.initialText;
            return f.options.contains(v) ? v : null;
          });
        case TaskFieldType.checkbox:
          _checks.putIfAbsent(f.key, () => f.initialChoices.toSet());
        default:
          final c = _text.putIfAbsent(f.key, TextEditingController.new);
          if (c.text.isEmpty) c.text = f.initialText;
      }
    }
  }

  Map<String, Object> _answers(List<TaskFormField> fields) {
    final answers = <String, Object>{};
    for (final f in fields) {
      switch (f.type) {
        case TaskFieldType.radio:
          answers[f.key] = _radio[f.key] ?? '';
        case TaskFieldType.checkbox:
          answers[f.key] = (_checks[f.key] ?? const <String>{}).toList();
        default:
          answers[f.key] = _text[f.key]?.text.trim() ?? '';
      }
    }
    return answers;
  }

  Future<void> _submit() async {
    final form = widget.state.form;
    if (form == null || widget.state.submitting) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return _toast('Please fill all required fields.', AppTheme.danger);
    }

    final result = await widget.state.submit(_answers(form.fields));
    if (!mounted) return;

    // On failure keep everything the user entered and show the server's text.
    if (!result.ok) return _toast(result.message, AppTheme.danger);

    // The messenger belongs to the app root, so the snackbar survives the pop.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context, true);
    messenger.showSnackBar(
      SnackBar(content: Text(result.message), backgroundColor: AppTheme.success),
    );
  }

  void _toast(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final form = state.form;

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Task Form')),
      bottomNavigationBar: form == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.gutter,
                  8,
                  AppTheme.gutter,
                  16,
                ),
                child: FilledButton(
                  onPressed: state.submitting ? null : _submit,
                  child: Text(state.submitting ? 'Submitting…' : 'Submit'),
                ),
              ),
            ),
      body: form == null
          ? _placeholder(state)
          : GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: Form(
                key: _formKey,
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.gutter,
                    8,
                    AppTheme.gutter,
                    24,
                  ),
                  children: [
                    _Header(form: form),
                    const SizedBox(height: 20),
                    for (final f in form.fields) ...[
                      _FieldLabel(f.label, required: f.required),
                      _input(f),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _placeholder(TaskFormState state) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assignment_outlined, size: 38, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              state.error ?? 'Your department has no daily task form.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: state.load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _input(TaskFormField f) {
    switch (f.type) {
      case TaskFieldType.radio:
        return FormField<String>(
          validator: (_) =>
              f.required && _radio[f.key] == null ? 'Pick one option.' : null,
          builder: (field) => _Choices(
            options: f.options,
            selected: {if (_radio[f.key] != null) _radio[f.key]!},
            error: field.errorText,
            onTap: (o) {
              setState(() => _radio[f.key] = _radio[f.key] == o ? null : o);
              field.didChange(_radio[f.key]);
            },
          ),
        );

      case TaskFieldType.checkbox:
        final picked = _checks.putIfAbsent(f.key, () => <String>{});
        return FormField<Set<String>>(
          validator: (_) => f.required && picked.isEmpty
              ? 'Select at least one option.'
              : null,
          builder: (field) => _Choices(
            options: f.options,
            selected: picked,
            multi: true,
            error: field.errorText,
            onTap: (o) {
              setState(() {
                if (!picked.remove(o)) picked.add(o);
              });
              field.didChange(picked);
            },
          ),
        );

      case TaskFieldType.date:
        return TextFormField(
          controller: _text[f.key],
          readOnly: true,
          decoration: const InputDecoration(
            hintText: 'YYYY-MM-DD',
            suffixIcon: Icon(Icons.calendar_today_rounded, size: 19),
          ),
          validator: _requiredText(f),
          onTap: () => _pickDate(f),
        );

      case TaskFieldType.time:
        return TextFormField(
          controller: _text[f.key],
          readOnly: true,
          decoration: InputDecoration(
            hintText: f.isDuration ? 'Hours : minutes' : 'HH:MM',
            helperText: f.isDuration ? 'Hours : minutes spent' : null,
            suffixIcon: Icon(
              f.isDuration ? Icons.timelapse_rounded : Icons.schedule_rounded,
              size: 19,
            ),
          ),
          validator: _requiredText(f),
          onTap: () => _pickTime(f),
        );

      case TaskFieldType.textarea:
        return TextFormField(
          controller: _text[f.key],
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          scrollPadding: const EdgeInsets.only(bottom: 140),
          decoration: const InputDecoration(alignLabelWithHint: true),
          validator: _requiredText(f),
        );

      case TaskFieldType.email:
        return TextFormField(
          controller: _text[f.key],
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          scrollPadding: const EdgeInsets.only(bottom: 140),
          validator: (v) {
            final s = v?.trim() ?? '';
            if (s.isEmpty) return f.required ? 'This field is required.' : null;
            return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)
                ? null
                : 'Enter a valid email address.';
          },
        );

      case TaskFieldType.text:
        return TextFormField(
          controller: _text[f.key],
          textCapitalization: TextCapitalization.sentences,
          scrollPadding: const EdgeInsets.only(bottom: 140),
          validator: _requiredText(f),
        );
    }
  }

  FormFieldValidator<String> _requiredText(TaskFormField f) => (v) =>
      f.required && (v == null || v.trim().isEmpty)
          ? 'This field is required.'
          : null;

  static String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _pickDate(TaskFormField f) async {
    final controller = _text[f.key]!;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(controller.text) ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2, 12, 31),
    );
    if (picked == null) return;
    setState(() => controller.text =
        '${picked.year.toString().padLeft(4, '0')}-${_two(picked.month)}-${_two(picked.day)}');
  }

  Future<void> _pickTime(TaskFormField f) async {
    final controller = _text[f.key]!;
    final parts = controller.text.split(':');
    final initial = parts.length >= 2
        ? TimeOfDay(
            hour: (int.tryParse(parts[0]) ?? 0).clamp(0, 23),
            minute: (int.tryParse(parts[1]) ?? 0).clamp(0, 59),
          )
        : (f.isDuration
            ? const TimeOfDay(hour: 0, minute: 0)
            : TimeOfDay.now());
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      initialEntryMode:
          f.isDuration ? TimePickerEntryMode.input : TimePickerEntryMode.dial,
      helpText: f.isDuration ? 'HOURS : MINUTES SPENT' : null,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(
        () => controller.text = '${_two(picked.hour)}:${_two(picked.minute)}');
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.form});

  final TaskForm form;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.gutter),
      decoration: BoxDecoration(
        gradient: brandGradient(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            form.label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            form.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text.rich(
        TextSpan(
          text: text,
          children: [
            if (required)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: AppTheme.danger),
              ),
          ],
        ),
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Chips for radio (single choice) and checkbox (multiple choice) questions.
class _Choices extends StatelessWidget {
  const _Choices({
    required this.options,
    required this.selected,
    required this.onTap,
    this.multi = false,
    this.error,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onTap;
  final bool multi;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in options)
              multi
                  ? FilterChip(
                      label: Text(o),
                      selected: selected.contains(o),
                      onSelected: (_) => onTap(o),
                    )
                  : ChoiceChip(
                      label: Text(o),
                      selected: selected.contains(o),
                      onSelected: (_) => onTap(o),
                    ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}
