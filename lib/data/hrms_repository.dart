import 'api_client.dart';
import 'attendance_repository.dart';
import 'models.dart';

/// Live implementation against the HRMS API.
class HrmsRepository implements AttendanceRepository {
  HrmsRepository({ApiClient? client}) : client = client ?? ApiClient();

  final ApiClient client;

  // ------------------------------------------------------------------- auth

  @override
  Future<Employee> login({
    required String employeeId,
    required String password,
  }) async {
    if (employeeId.trim().isEmpty || password.isEmpty) {
      throw const AuthException('Enter your phone number and password.');
    }

    try {
      // `phone` also accepts an employee code or email, per the API contract.
      final json = await client.post('auth/login', body: {
        'phone': employeeId.trim(),
        'password': password,
        'device_info': 'Sanmarg Attendance mobile app',
      });

      final data = payloadOf(json);
      final token = pick(data, ['token', 'access_token', 'api_token']);
      if (token == null) {
        throw const AuthException('Server did not return a session token.');
      }
      await client.setToken('$token');

      final user = pick(data, ['user', 'employee', 'profile']);
      if (user is Map<String, dynamic>) return Employee.fromJson(user);

      // Some deployments return only the token — fetch the profile separately.
      return currentUser();
    } on ApiException catch (e) {
      throw AuthException(e.message);
    }
  }

  /// Restores a session from a stored token. Null if there is none or it has
  /// been revoked server-side.
  @override
  Future<Employee?> restoreSession() async {
    await client.loadToken();
    if (!client.hasToken) return null;
    try {
      return await currentUser();
    } catch (_) {
      await client.setToken(null);
      return null;
    }
  }

  Future<Employee> currentUser() async {
    final json = await client.get('auth/me');
    final data = payloadOf(json);
    final user = pick(data, ['user', 'employee', 'profile']);
    return Employee.fromJson(
      user is Map<String, dynamic> ? user : data,
    );
  }

  @override
  Future<void> logout() async {
    try {
      await client.post('auth/logout');
    } catch (_) {
      // Clearing the local token matters more than the server round-trip.
    }
    await client.setToken(null);
  }

  // ------------------------------------------------------------- attendance

  @override
  Future<DayStatus> todayStatus() async {
    final json = await client.get('attendance/today');
    final data = payloadOf(json);

    // The endpoint may nest the record under `attendance` / `today`.
    final record = pick(data, ['attendance', 'today', 'record']);
    return DayStatus.fromJson(
      record is Map<String, dynamic> ? record : data,
    );
  }

  @override
  Future<DayStatus> checkIn(PunchContext context) =>
      _punch('attendance/punch_in', context);

  @override
  Future<DayStatus> checkOut(PunchContext context) =>
      _punch('attendance/punch_out', context);

  Future<DayStatus> _punch(String path, PunchContext context) async {
    if (context.selfieBase64 == null) {
      throw const ApiException('A selfie is required to record your punch.');
    }
    if (context.latitude == null || context.longitude == null) {
      throw const ApiException(
        'Location is required to record your punch. Enable GPS and retry.',
      );
    }

    final json = await client.post(path, body: {
      'selfie_image': context.selfieBase64,
      'latitude': context.latitude,
      'longitude': context.longitude,
      if (context.accuracy != null) 'accuracy': context.accuracy,
    });

    // The punch endpoints echo back the row they just wrote, so the caller
    // can update the dashboard immediately from this response instead of
    // paying for a second round trip to `attendance/today` - that used to
    // double the time a punch took to visibly register.
    final data = payloadOf(json);
    final record = pick(data, ['attendance', 'punch', 'record']);
    return DayStatus.fromJson(record is Map<String, dynamic> ? record : data);
  }

  /// Periodic location ping while a user is punched in (field staff tracking).
  Future<void> track(PunchContext context) async {
    if (context.latitude == null || context.longitude == null) return;
    try {
      await client.post('attendance/track', body: {
        'latitude': context.latitude,
        'longitude': context.longitude,
        if (context.accuracy != null) 'accuracy': context.accuracy,
        'address': context.address,
      });
    } catch (_) {
      // Tracking is best-effort; never surface a failure to the user.
    }
  }
}
