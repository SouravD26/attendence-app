import 'package:flutter/foundation.dart';

import '../data/attendance_api.dart';
import '../data/attendance_models.dart';
import '../data/models.dart';

/// Drives the attendance tab: which month is selected, and what it holds.
class AttendanceState extends ChangeNotifier {
  AttendanceState(this._api) : _month = _firstOf(DateTime.now());

  final AttendanceApi _api;

  /// Always the first of the month, so equality and labelling are simple.
  DateTime _month;
  MonthAttendance _data = MonthAttendance.empty;
  bool _loading = false;
  String? _error;

  DateTime get month => _month;
  MonthAttendance get data => _data;
  List<AttendanceDay> get days => _data.days;
  MonthStats get stats => _data.stats;
  bool get loading => _loading;
  String? get error => _error;

  bool get isCurrentMonth => _month == _firstOf(DateTime.now());

  /// There is nothing to show for a month that has not started.
  bool get canGoForward => _month.isBefore(_firstOf(DateTime.now()));

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _data = await _api.month(_month);
    } on ApiException catch (e) {
      _error = e.message;
      _data = MonthAttendance.empty;
    } catch (_) {
      _error = 'Could not load attendance for this month.';
      _data = MonthAttendance.empty;
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> setMonth(DateTime value) async {
    final normalised = _firstOf(value);
    if (normalised == _month) return;
    _month = normalised;
    _data = MonthAttendance.empty;
    await load();
  }

  Future<void> step(int months) =>
      setMonth(DateTime(_month.year, _month.month + months));

  static DateTime _firstOf(DateTime d) => DateTime(d.year, d.month);
}
