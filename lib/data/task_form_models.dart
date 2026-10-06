// Department daily-task form, mapped from the `forms` endpoint.
//
// The questions mirror the department's Google Form and differ per team, so
// the screen is built from [TaskFormField]s rather than hardcoded widgets.

import 'api_client.dart';

enum TaskFieldType { text, textarea, email, radio, checkbox, date, time }

TaskFieldType taskFieldTypeFrom(Object? raw) {
  switch ('${raw ?? ''}'.trim().toLowerCase()) {
    case 'textarea':
    case 'paragraph':
      return TaskFieldType.textarea;
    case 'email':
      return TaskFieldType.email;
    case 'radio':
      return TaskFieldType.radio;
    case 'checkbox':
      return TaskFieldType.checkbox;
    case 'date':
      return TaskFieldType.date;
    case 'time':
      return TaskFieldType.time;
    default:
      return TaskFieldType.text;
  }
}

class TaskFormField {
  final String key;
  final TaskFieldType type;
  final String label;
  final bool required;
  final List<String> options;

  /// A time field that means "hours : minutes spent", not a clock time.
  final bool isDuration;

  /// Prefill: a string, or a list of strings for checkbox fields.
  final Object? value;

  const TaskFormField({
    required this.key,
    required this.type,
    required this.label,
    this.required = false,
    this.options = const [],
    this.isDuration = false,
    this.value,
  });

  factory TaskFormField.fromJson(Map<String, dynamic> json) {
    final options = json['options'];
    return TaskFormField(
      key: '${json['key'] ?? ''}',
      type: taskFieldTypeFrom(json['type']),
      label: '${json['label'] ?? ''}',
      required: _flag(json['required']),
      options: options is List ? options.map((e) => '$e').toList() : const [],
      isDuration: _flag(json['is_duration']),
      value: json['value'],
    );
  }

  String get initialText {
    final v = value;
    if (v == null || v is List) return '';
    return '$v';
  }

  List<String> get initialChoices {
    final v = value;
    if (v is List) return v.map((e) => '$e').toList();
    if (v is String && v.isNotEmpty) return [v];
    return const [];
  }
}

class TaskForm {
  final String label;
  final String title;
  final List<TaskFormField> fields;

  const TaskForm({
    required this.label,
    required this.title,
    required this.fields,
  });

  factory TaskForm.fromJson(Map<String, dynamic> json) => TaskForm(
        label: '${json['label'] ?? ''}',
        title: '${json['title'] ?? ''}',
        fields: listOf(json, 'fields').map(TaskFormField.fromJson).toList(),
      );
}

/// `forms` — only some departments have a form; [form] is null otherwise.
class TaskFormInfo {
  final bool hasForm;
  final String? department;
  final TaskForm? form;

  const TaskFormInfo({this.hasForm = false, this.department, this.form});

  static const none = TaskFormInfo();

  factory TaskFormInfo.fromJson(Map<String, dynamic> json) {
    final form = json['form'];
    final parsed = form is Map<String, dynamic> ? TaskForm.fromJson(form) : null;
    return TaskFormInfo(
      hasForm: _flag(json['has_form']) && parsed != null,
      department: json['department']?.toString(),
      form: parsed,
    );
  }
}

bool _flag(Object? v) => v == true || v == 1 || v == '1' || v == 'yes';
