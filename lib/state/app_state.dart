import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/attendance_repository.dart';
import '../data/models.dart';

enum AuthStatus { restoring, signedOut, signingIn, signedIn }

/// Single source of truth for the session and today's attendance.
///
/// Deliberately a plain [ChangeNotifier] — no extra state package to learn,
/// and it drops straight into provider/riverpod later if the app grows.
class AppState extends ChangeNotifier {
  AppState(this._repo);

  final AttendanceRepository _repo;

  AuthStatus _auth = AuthStatus.restoring;
  Employee? _employee;
  DayStatus? _today;
  bool _busy = false;
  String? _error;
  Timer? _ticker;

  AuthStatus get auth => _auth;
  Employee? get employee => _employee;
  DayStatus? get today => _today;
  bool get busy => _busy;
  String? get error => _error;

  /// Ticks once a second while checked in so the live timer stays honest.
  void _syncTicker() {
    final needsTicker = _today?.isCheckedIn ?? false;
    if (needsTicker && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => notifyListeners(),
      );
    } else if (!needsTicker) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  /// Called once at startup: re-enters the app if a stored token still works.
  Future<void> restoreSession() async {
    try {
      _employee = await _repo.restoreSession();
    } catch (_) {
      _employee = null;
    }
    if (_employee == null) {
      _auth = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    _auth = AuthStatus.signedIn;
    notifyListeners();
    await refresh();
  }

  Future<bool> login(String employeeId, String password) async {
    _auth = AuthStatus.signingIn;
    _error = null;
    notifyListeners();
    try {
      _employee = await _repo.login(employeeId: employeeId, password: password);
      _auth = AuthStatus.signedIn;
      notifyListeners();
      await refresh();
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      _auth = AuthStatus.signedOut;
      notifyListeners();
      return false;
    } on ApiException catch (e) {
      _error = e.message;
      _auth = AuthStatus.signedOut;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Could not reach the server. Check your connection.';
      _auth = AuthStatus.signedOut;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    _ticker?.cancel();
    _ticker = null;
    _auth = AuthStatus.signedOut;
    _employee = null;
    _today = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    try {
      _today = await _repo.todayStatus();
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not load today\'s attendance.';
    }
    _syncTicker();
    notifyListeners();
  }

  /// Punches in or out depending on current state. Returns the punch that was
  /// recorded so the UI can show the right confirmation.
  Future<PunchType> punch(PunchContext context) async {
    if (_busy) return PunchType.none;
    _busy = true;
    _error = null;
    notifyListeners();
    final goingIn = !(_today?.isCheckedIn ?? false);
    try {
      if (goingIn) {
        await _repo.checkIn(context);
      } else {
        await _repo.checkOut(context);
      }

      // Flip the dashboard the instant the punch is accepted, using the
      // device clock rather than waiting on a second round trip just to
      // read back a time we already know. `refresh()` reconciles the exact
      // server totals afterwards in the background, without making the
      // button sit and spin for it.
      final now = DateTime.now();
      final base = _today ?? DayStatus(date: now);
      _today = goingIn
          ? base.copyWith(checkIn: now, checkedIn: true)
          : base.copyWith(
              checkOut: now,
              checkedIn: false,
              priorWorked: base.checkIn != null
                  ? base.priorWorked + now.difference(base.checkIn!)
                  : base.priorWorked,
            );

      unawaited(refresh());
      return goingIn ? PunchType.checkIn : PunchType.checkOut;
    } on ApiException catch (e) {
      _error = e.message;
      return PunchType.none;
    } catch (_) {
      _error = 'Punch failed. Please try again.';
      return PunchType.none;
    } finally {
      _busy = false;
      _syncTicker();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
