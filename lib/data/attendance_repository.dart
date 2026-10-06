import 'models.dart';

/// The single seam between UI and backend.
///
/// The UI only ever talks to this interface. [HrmsRepository] is the live
/// implementation; [MockAttendanceRepository] below keeps the app runnable
/// offline and in tests.
abstract class AttendanceRepository {
  Future<Employee> login({required String employeeId, required String password});

  /// Returns the signed-in employee if a stored token is still valid, else null.
  Future<Employee?> restoreSession();
  Future<void> logout();

  Future<DayStatus> todayStatus();
  Future<DayStatus> checkIn(PunchContext context);
  Future<DayStatus> checkOut(PunchContext context);
}

/// In-memory implementation so the whole app is runnable and demoable today.
class MockAttendanceRepository implements AttendanceRepository {
  DayStatus _today = DayStatus(date: DateTime.now());

  static const _latency = Duration(milliseconds: 650);

  @override
  Future<Employee> login({
    required String employeeId,
    required String password,
  }) async {
    await Future.delayed(_latency);
    if (employeeId.trim().isEmpty || password.isEmpty) {
      throw const AuthException('Enter your employee ID and password.');
    }
    if (password.length < 4) {
      throw const AuthException('Incorrect password. Please try again.');
    }
    return Employee(
      id: employeeId.trim().toUpperCase(),
      name: 'Sanmarg Employee',
      designation: 'Senior Executive',
      department: 'Operations',
    );
  }

  @override
  Future<Employee?> restoreSession() async => null;

  @override
  Future<void> logout() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _today = DayStatus(date: DateTime.now());
  }

  @override
  Future<DayStatus> todayStatus() async {
    await Future.delayed(_latency);
    return _today;
  }

  @override
  Future<DayStatus> checkIn(PunchContext context) async {
    await Future.delayed(_latency);
    final now = DateTime.now();
    _today = _today.copyWith(
      checkIn: now,
      location: context.address,
      checkedIn: true,
    );
    return _today;
  }

  @override
  Future<DayStatus> checkOut(PunchContext context) async {
    await Future.delayed(_latency);
    final now = DateTime.now();
    _today = _today.copyWith(
      checkOut: now,
      checkedIn: false,
      priorWorked: _today.checkIn != null
          ? _today.priorWorked + now.difference(_today.checkIn!)
          : _today.priorWorked,
    );
    return _today;
  }
}
