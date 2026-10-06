import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../data/task_form_api.dart';
import '../data/task_form_models.dart';

/// Whether the signed-in employee's department has a daily-task form, and
/// submitting it. The dashboard hides the entry point until [hasForm].
class TaskFormState extends ChangeNotifier {
  TaskFormState(this.api);

  final TaskFormApi api;

  TaskFormInfo _info = TaskFormInfo.none;
  bool _loading = false;
  bool _submitting = false;
  String? _error;

  TaskFormInfo get info => _info;
  TaskForm? get form => _info.form;
  bool get hasForm => _info.hasForm;
  bool get loading => _loading;
  bool get submitting => _submitting;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _info = await api.fetch();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not load your daily task form.';
    }
    _loading = false;
    notifyListeners();
  }

  /// Forgets the previous employee's form. Silent: called from initState,
  /// before anything listens.
  void clear() {
    _info = TaskFormInfo.none;
    _error = null;
  }

  /// Returns (ok, message) — the server's message either way.
  Future<({bool ok, String message})> submit(Map<String, Object> answers) async {
    if (_submitting) return (ok: false, message: 'Already submitting…');
    _submitting = true;
    notifyListeners();
    try {
      final message = await api.submit(answers);
      return (ok: true, message: message);
    } on ApiException catch (e) {
      return (ok: false, message: e.message);
    } catch (_) {
      return (ok: false, message: 'Could not submit the form. Please try again.');
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }
}
