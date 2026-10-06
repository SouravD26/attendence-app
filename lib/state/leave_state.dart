import 'package:flutter/foundation.dart';

import '../data/leave_api.dart';
import '../data/leave_models.dart';
import '../data/models.dart';

/// Leave tab state. Same plain-ChangeNotifier style as [AppState].
class LeaveState extends ChangeNotifier {
  LeaveState(this._api);

  final LeaveApi _api;

  List<LeaveType> _types = const [];
  List<LeaveBalance> _balance = const [];
  List<LeaveApplication> _applications = const [];

  /// Every application regardless of status, backing the headline figures.
  List<LeaveApplication> _everything = const [];
  String _filter = 'all';
  bool _loading = false;
  bool _submitting = false;
  String? _error;

  List<LeaveType> get types => _types;
  List<LeaveBalance> get balance => _balance;
  List<LeaveApplication> get applications => _applications;
  String get filter => _filter;
  bool get loading => _loading;
  bool get submitting => _submitting;
  String? get error => _error;

  /// Total days still available across every leave type.
  double get totalBalance =>
      _balance.fold<double>(0, (sum, b) => sum + b.balance);

  /// Headline figures, counted from the employee's own applications.
  ///
  /// `leave/balance` is the natural source, but every type currently reports a
  /// zero allowance, so the applications are what actually carry the numbers.
  /// The status filter is applied server-side, so the headline figures read
  /// from their own unfiltered copy rather than whatever the list is showing.

  double get approvedDays => _sumDays(LeaveStatus.approved);
  double get pendingDays => _sumDays(LeaveStatus.pending);
  int get approvedCount => _countOf(LeaveStatus.approved);
  int get pendingCount => _countOf(LeaveStatus.pending);

  /// Days actually consumed: what the server reports as used, falling back to
  /// the approved applications when no allowance is configured.
  double get takenDays {
    final used = _balance.fold<double>(0, (sum, b) => sum + b.used);
    return used > 0 ? used : approvedDays;
  }

  double _sumDays(LeaveStatus status) => _everything
      .where((l) => l.status == status)
      .fold<double>(0, (sum, l) => sum + l.days);

  int _countOf(LeaveStatus status) =>
      _everything.where((l) => l.status == status).length;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      // The calls are independent; run them together.
      final results = await Future.wait([
        _api.types(),
        _api.balance(),
        _api.list(status: 'all'),
        if (_filter != 'all') _api.list(status: _filter),
      ]);
      _types = results[0] as List<LeaveType>;
      _balance = results[1] as List<LeaveBalance>;
      _everything = results[2] as List<LeaveApplication>;
      _applications = _filter == 'all'
          ? _everything
          : results[3] as List<LeaveApplication>;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not load your leave records.';
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> setFilter(String value) async {
    if (_filter == value) return;
    _filter = value;
    notifyListeners();
    await _reloadList();
  }

  Future<void> _reloadList() async {
    try {
      _applications = await _api.list(status: _filter);
      if (_filter == 'all') _everything = _applications;
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not load your leave applications.';
    }
    notifyListeners();
  }

  /// Returns null on success, or the message to show the user.
  Future<String?> apply({
    required String leaveType,
    required DateTime start,
    required DateTime end,
    required String reason,
  }) async {
    if (_submitting) return null;
    _submitting = true;
    notifyListeners();
    try {
      await _api.apply(
        leaveType: leaveType,
        start: start,
        end: end,
        reason: reason,
      );
      await load();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not submit your request. Please try again.';
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  Future<String?> cancel(String id) async {
    try {
      await _api.cancel(id);
      await load();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not cancel this request.';
    }
  }
}
