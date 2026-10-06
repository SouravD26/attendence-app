// Models for the monthly attendance view, mapped from `attendance/summary`
// (falling back to `attendance/history`).

import 'api_client.dart';
import 'models.dart';

/// How a single day is classified. The server sends a free-text status, so
/// [dayStatusFrom] folds the spellings it uses into something the UI can
/// colour and count.
enum DayMark {
  present,
  absent,
  leave,
  holiday,
  weekOff,
  halfDay,
  onDuty,
  compOff,
  unknown,
}

DayMark dayStatusFrom(Object? raw) {
  final s = '${raw ?? ''}'.trim().toLowerCase().replaceAll(RegExp(r'[\s-]'), '_');
  switch (s) {
    case 'p':
    case 'present':
      return DayMark.present;
    case 'a':
    case 'absent':
      return DayMark.absent;
    case 'l':
    case 'leave':
    case 'on_leave':
      return DayMark.leave;
    case 'h':
    case 'holiday':
      return DayMark.holiday;
    case 'wo':
    case 'week_off':
    case 'weekoff':
    case 'weekly_off':
      return DayMark.weekOff;
    case 'hd':
    case 'half_day':
    case 'halfday':
      return DayMark.halfDay;
    case 'od':
    case 'on_duty':
      return DayMark.onDuty;
    case 'comp_off':
    case 'compoff':
    case 'co':
      return DayMark.compOff;
    default:
      return DayMark.unknown;
  }
}

String dayMarkLabel(DayMark mark) {
  switch (mark) {
    case DayMark.present:
      return 'Present';
    case DayMark.absent:
      return 'Absent';
    case DayMark.leave:
      return 'Leave';
    case DayMark.holiday:
      return 'Holiday';
    case DayMark.weekOff:
      return 'Week off';
    case DayMark.halfDay:
      return 'Half day';
    case DayMark.onDuty:
      return 'On duty';
    case DayMark.compOff:
      return 'Comp off';
    case DayMark.unknown:
      return '—';
  }
}

/// One row in the month list.
class AttendanceDay {
  final DateTime date;
  final DateTime? punchIn;
  final DateTime? punchOut;
  final Duration worked;
  final DayMark mark;
  final String? location;

  /// The API's own flag for a day with a punch-in and no punch-out.
  final bool incomplete;

  /// How many punch pairs the day holds. More than one means the in/out times
  /// above come from different pairs - earliest in, latest out - so they do
  /// not describe a single continuous shift.
  final int punchCount;

  const AttendanceDay({
    required this.date,
    this.punchIn,
    this.punchOut,
    this.worked = Duration.zero,
    this.mark = DayMark.unknown,
    this.location,
    this.incomplete = false,
    this.punchCount = 0,
  });

  /// Punched in but never out — the row the employee most needs to notice.
  /// Trust the server's flag when it sends one; infer it otherwise.
  bool get isOpen =>
      incomplete || (punchIn != null && punchOut == null);

  factory AttendanceDay.fromJson(Map<String, dynamic> json) {
    final date = parseDate(
          pick(json, ['date', 'attendance_date', 'day', 'punch_date']),
        ) ??
        DateTime.now();

    final punchIn = parseDateTime(
      pick(json, ['punch_in', 'check_in', 'in_time', 'first_in']),
      onDate: date,
    );
    var punchOut = parseDateTime(
      pick(json, ['punch_out', 'check_out', 'out_time', 'last_out']),
      onDate: date,
    );

    // Night shifts close after midnight; without this the pair reads as a
    // negative span and the day shows zero hours.
    if (punchIn != null && punchOut != null && punchOut.isBefore(punchIn)) {
      punchOut = punchOut.add(const Duration(days: 1));
    }

    return AttendanceDay(
      date: date,
      punchIn: punchIn,
      punchOut: punchOut,
      worked: _worked(json, punchIn, punchOut),
      // `attendance/summary` types the day under `type`; the per-punch rows
      // from `attendance/history` use `status`.
      mark: dayStatusFrom(
        pick(json, ['type', 'status', 'attendance_status', 'mark']),
      ),
      location: pick(json, [
        'punch_in_location',
        'punch_out_location',
        'punch_in_address',
        'address',
        'location',
      ])?.toString(),
      incomplete: json['incomplete'] == true || json['incomplete'] == 1,
      punchCount: _count(pick(json, ['punch_count', 'punches_count'])),
    );
  }

  static int _count(Object? v) =>
      v == null ? 0 : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

  /// Prefer the server's own total (it applies the shift rules); fall back to
  /// the punch pair only when it sends none.
  static Duration _worked(
    Map<String, dynamic> json,
    DateTime? punchIn,
    DateTime? punchOut,
  ) {
    // `worked_minutes` is explicit about its unit, so it is safest of all —
    // read as hours it would turn 517 minutes into 517 hours.
    final minutes = pick(json, ['worked_minutes', 'total_minutes']);
    if (minutes != null) {
      final n = minutes is num ? minutes.toInt() : int.tryParse('$minutes');
      if (n != null && n >= 0) return Duration(minutes: n);
    }

    final parsed = parseDuration(pick(json, [
      'worked_hours',
      'total_hours',
      'working_hours',
      'hours',
      'duration',
    ]));
    if (parsed != null) return parsed;

    if (punchIn != null && punchOut != null) {
      return punchOut.difference(punchIn);
    }
    return Duration.zero;
  }
}

/// Month totals shown above the list.
class MonthStats {
  final int present;
  final int absent;
  final int leave;
  final int holiday;
  final int weekOff;
  final int halfDay;
  final int onDuty;
  final int compOff;
  final int incomplete;
  final int payableDays;
  final Duration totalWorked;

  const MonthStats({
    this.present = 0,
    this.absent = 0,
    this.leave = 0,
    this.holiday = 0,
    this.weekOff = 0,
    this.halfDay = 0,
    this.onDuty = 0,
    this.compOff = 0,
    this.incomplete = 0,
    this.payableDays = 0,
    this.totalWorked = Duration.zero,
  });

  /// Derived from the rows when the server sends no stats block, so the
  /// header is never blank while the list has content.
  factory MonthStats.fromDays(List<AttendanceDay> days) {
    var present = 0, absent = 0, leave = 0, holiday = 0, weekOff = 0, half = 0;
    var onDuty = 0, compOff = 0, incomplete = 0;
    var total = Duration.zero;

    for (final d in days) {
      total += d.worked;
      if (d.isOpen) incomplete++;
      switch (d.mark) {
        case DayMark.onDuty:
          onDuty++;
          present++;
        case DayMark.compOff:
          compOff++;
        case DayMark.present:
          present++;
        case DayMark.absent:
          absent++;
        case DayMark.leave:
          leave++;
        case DayMark.holiday:
          holiday++;
        case DayMark.weekOff:
          weekOff++;
        case DayMark.halfDay:
          half++;
        case DayMark.unknown:
          // An unmarked day with a punch still counts as attended.
          if (d.punchIn != null) present++;
      }
    }

    return MonthStats(
      present: present,
      absent: absent,
      leave: leave,
      holiday: holiday,
      weekOff: weekOff,
      halfDay: half,
      onDuty: onDuty,
      compOff: compOff,
      incomplete: incomplete,
      // Days the employee is paid for, when the server does not say.
      payableDays: present + leave + holiday + weekOff + compOff,
      totalWorked: total,
    );
  }

  factory MonthStats.fromJson(Map<String, dynamic> json) => MonthStats(
        present: _int(pick(json, ['present', 'present_days', 'total_present'])),
        absent: _int(pick(json, ['absent', 'absent_days', 'total_absent'])),
        leave: _int(pick(json, ['leave', 'leave_days', 'total_leave'])),
        holiday: _int(pick(json, ['holiday', 'holidays', 'holiday_days'])),
        weekOff: _int(pick(json, ['week_off', 'weekoff', 'week_offs'])),
        halfDay: _int(pick(json, ['half_day', 'half_days', 'halfday'])),
        onDuty: _int(pick(json, ['od', 'on_duty', 'od_days'])),
        compOff: _int(pick(json, ['comp_off', 'compoff', 'comp_off_days'])),
        incomplete: _int(pick(json, ['incomplete', 'incomplete_days'])),
        payableDays: _int(pick(json, ['payable_days', 'payable'])),
        totalWorked: _totalWorked(json),
      );

  /// Same unit trap as a day's hours: prefer the labelled minutes.
  static Duration _totalWorked(Map<String, dynamic> json) {
    final minutes = pick(json, ['worked_minutes', 'total_minutes']);
    if (minutes != null) {
      final n = minutes is num ? minutes.toInt() : int.tryParse('$minutes');
      if (n != null && n >= 0) return Duration(minutes: n);
    }
    return parseDuration(pick(json, [
          'worked_hours',
          'total_hours',
          'total_working_hours',
        ])) ??
        Duration.zero;
  }

  static int _int(Object? v) =>
      v == null ? 0 : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
}

/// Everything the attendance screen shows for one month.
class MonthAttendance {
  final List<AttendanceDay> days;
  final MonthStats stats;

  const MonthAttendance({required this.days, required this.stats});

  static const empty = MonthAttendance(days: [], stats: MonthStats());
}

/// Accepts `8.5` (hours), `08:30` / `8:30:00` (clock), and `510` only when the
/// server labels it minutes elsewhere — bare integers are read as hours, which
/// is what every HRMS field here uses.
Duration? parseDuration(Object? value) {
  if (value == null) return null;

  if (value is num) {
    if (value <= 0) return Duration.zero;
    return Duration(minutes: (value * 60).round());
  }

  final raw = '$value'.trim();
  if (raw.isEmpty) return null;

  final clock = RegExp(r'^(\d{1,3}):(\d{2})(?::(\d{2}))?$').firstMatch(raw);
  if (clock != null) {
    return Duration(
      hours: int.parse(clock.group(1)!),
      minutes: int.parse(clock.group(2)!),
      seconds: int.parse(clock.group(3) ?? '0'),
    );
  }

  final hours = double.tryParse(raw);
  if (hours == null) return null;
  if (hours <= 0) return Duration.zero;
  return Duration(minutes: (hours * 60).round());
}

/// `9h 05m`, the format used across the attendance screens.
String formatWorked(Duration d) {
  if (d <= Duration.zero) return '—';
  return '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
}
