// Plain data models.
//
// The `fromJson` mappings accept a few aliases per field, because the HRMS
// endpoints are not perfectly uniform in their naming. `pick` in api_client.dart
// does the alias resolution.

import 'api_client.dart';

class Employee {
  final String id;
  final String name;
  final String designation;
  final String department;
  final String? photoUrl;
  final String? phone;
  final String? employeeCode;
  final bool isAdmin;

  /// Whether this user does ticket work, and whether they may assign it.
  /// Both come from the server so the rules are never re-implemented here.
  final bool isItStaff;
  final bool isSuperAdmin;

  const Employee({
    required this.id,
    required this.name,
    required this.designation,
    required this.department,
    this.photoUrl,
    this.phone,
    this.employeeCode,
    this.isAdmin = false,
    this.isItStaff = false,
    this.isSuperAdmin = false,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    final role = '${pick(json, ['role', 'user_type', 'type']) ?? ''}'.toLowerCase();
    return Employee(
      id: '${pick(json, ['id', 'user_id', 'employee_id']) ?? ''}',
      name: '${pick(json, ['name', 'full_name', 'employee_name']) ?? ''}',
      designation: '${pick(json, ['designation', 'title', 'post']) ?? ''}',
      department: '${pick(json, ['department', 'department_name', 'dept']) ?? ''}',
      photoUrl: pick(json, ['photo_url', 'photo', 'image', 'avatar'])?.toString(),
      phone: pick(json, ['phone', 'mobile', 'contact_number'])?.toString(),
      employeeCode:
          pick(json, ['employee_code', 'emp_code', 'code'])?.toString(),
      isAdmin: json['is_admin'] == true ||
          json['is_admin'] == 1 ||
          role == 'admin' ||
          role == 'hr',
      // The server reports this; fall back to the same rule it uses when an
      // older deployment does not send the field, so the IT section is not
      // hidden purely because the API has not been updated yet.
      isItStaff: json.containsKey('is_it_staff')
          ? (json['is_it_staff'] == true || json['is_it_staff'] == 1)
          : (role == 'it' ||
              role == 'superadmin' ||
              '${pick(json, ['department', 'department_name', 'dept']) ?? ''}'
                      .trim()
                      .toUpperCase() ==
                  'IT'),
      isSuperAdmin: json['is_superadmin'] == true ||
          json['is_superadmin'] == 1 ||
          role == 'superadmin',
    );
  }
}

enum PunchType { none, checkIn, checkOut }

/// Everything the dashboard needs for the current day, in one object.
class DayStatus {
  final DateTime date;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final String? location;
  final Duration shiftLength;

  /// Whether there is currently an open punch (no punch-out yet). The
  /// backend is the source of truth for this (`is_punched_in`) because the
  /// server now allows more than one punch-in/out pair per day, so it can no
  /// longer be inferred from [checkIn]/[checkOut] alone.
  final bool checkedIn;

  /// Minutes already banked from punches that are already closed today. The
  /// still-open session (if any) is added to this live, on top.
  final Duration priorWorked;

  /// Whether the day should be treated as permanently done (no more
  /// punching in). The live `attendance/today` summary allows punching back
  /// in after a punch-out, so this is only ever true for the legacy
  /// single-record shape (mock repository / older deployments).
  final bool locked;

  const DayStatus({
    required this.date,
    this.checkIn,
    this.checkOut,
    this.location,
    this.shiftLength = const Duration(hours: 9),
    this.checkedIn = false,
    this.priorWorked = Duration.zero,
    this.locked = false,
  });

  bool get isCheckedIn => checkedIn;
  bool get isComplete => locked;

  /// Time worked so far - live while checked in, final once checked out.
  Duration workedAt(DateTime now) {
    if (checkedIn && checkIn != null) {
      return priorWorked + now.difference(checkIn!);
    }
    return priorWorked;
  }

  /// 0..1 progress against the expected shift, for the dial.
  double progressAt(DateTime now) {
    final worked = workedAt(now).inSeconds / shiftLength.inSeconds;
    return worked.clamp(0.0, 1.0);
  }

  DayStatus copyWith({
    DateTime? checkIn,
    DateTime? checkOut,
    String? location,
    bool? checkedIn,
    Duration? priorWorked,
    bool? locked,
  }) =>
      DayStatus(
        date: date,
        checkIn: checkIn ?? this.checkIn,
        checkOut: checkOut ?? this.checkOut,
        location: location ?? this.location,
        shiftLength: shiftLength,
        checkedIn: checkedIn ?? this.checkedIn,
        priorWorked: priorWorked ?? this.priorWorked,
        locked: locked ?? this.locked,
      );

  factory DayStatus.fromJson(Map<String, dynamic> json) {
    // `attendance/today` summary shape (is_punched_in / open_punch /
    // first_punch_in / last_punch_out / worked_minutes), which allows
    // multiple punch in/out pairs per day.
    if (json.containsKey('is_punched_in') ||
        json.containsKey('open_punch') ||
        json.containsKey('can_punch_in')) {
      final date = parseDate(json['date']) ?? DateTime.now();
      final checkedIn = json['is_punched_in'] == true;
      final openPunch = json['open_punch'];
      final openCheckIn = openPunch is Map<String, dynamic>
          ? parseDateTime(openPunch['punch_in'], onDate: date)
          : null;
      final worked = json['worked_minutes'];
      return DayStatus(
        date: date,
        checkIn: checkedIn
            ? openCheckIn
            : parseDateTime(json['first_punch_in'], onDate: date),
        checkOut: parseDateTime(json['last_punch_out'], onDate: date),
        checkedIn: checkedIn,
        priorWorked: Duration(
          minutes: worked is num ? worked.round() : 0,
        ),
      );
    }

    // Legacy / single-record shape - still used by the mock repository and
    // kept as a fallback for older deployments.
    final date = parseDate(pick(json, ['date', 'attendance_date', 'day'])) ??
        DateTime.now();
    final checkIn = parseDateTime(
      pick(json, ['punch_in', 'check_in', 'in_time', 'punch_in_time']),
      onDate: date,
    );
    final checkOut = parseDateTime(
      pick(json, ['punch_out', 'check_out', 'out_time', 'punch_out_time']),
      onDate: date,
    );
    return DayStatus(
      date: date,
      checkIn: checkIn,
      checkOut: checkOut,
      location: pick(json, [
        'punch_in_address',
        'address',
        'location',
        'punch_in_location',
      ])?.toString(),
      shiftLength: parseShift(pick(json, ['shift_hours', 'working_hours'])),
      checkedIn: checkIn != null && checkOut == null,
      priorWorked: checkIn != null && checkOut != null
          ? checkOut.difference(checkIn)
          : Duration.zero,
      locked: checkIn != null && checkOut != null,
    );
  }
}

/// Where the punch happened, captured at the moment the button is pressed.
class PunchContext {
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final String address;

  /// Base64 data URI of the selfie, ready for `selfie_image`.
  final String? selfieBase64;

  /// Local file path, used only to render the preview in the sheet.
  final String? selfiePath;

  const PunchContext({
    this.latitude,
    this.longitude,
    this.accuracy,
    required this.address,
    this.selfieBase64,
    this.selfiePath,
  });

  PunchContext copyWith({String? selfieBase64, String? selfiePath}) =>
      PunchContext(
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        address: address,
        selfieBase64: selfieBase64 ?? this.selfieBase64,
        selfiePath: selfiePath ?? this.selfiePath,
      );
}

// --------------------------------------------------------------- parsing

/// Accepts 'YYYY-MM-DD', ISO timestamps, and epoch seconds.
DateTime? parseDate(Object? value) {
  if (value == null) return null;
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value * 1000);
  }
  return DateTime.tryParse('$value'.replaceFirst(' ', 'T'));
}

/// Accepts full timestamps and bare 'HH:mm:ss' times, which the attendance
/// endpoints return alongside a separate date field.
DateTime? parseDateTime(Object? value, {DateTime? onDate}) {
  if (value == null) return null;
  final raw = '$value'.trim();
  if (raw.isEmpty || raw == '00:00:00' || raw.toLowerCase() == 'null') {
    return null;
  }

  final full = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  if (full != null) return full;

  final time = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(raw);
  if (time == null) return null;

  final day = onDate ?? DateTime.now();
  return DateTime(
    day.year,
    day.month,
    day.day,
    int.parse(time.group(1)!),
    int.parse(time.group(2)!),
    int.parse(time.group(3) ?? '0'),
  );
}

/// Expected shift length, defaulting to 9 hours when the server omits it.
Duration parseShift(Object? value) {
  final hours = value is num ? value.toDouble() : double.tryParse('$value');
  if (hours == null || hours <= 0) return const Duration(hours: 9);
  return Duration(minutes: (hours * 60).round());
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}
