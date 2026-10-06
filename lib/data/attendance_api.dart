import 'api_client.dart';
import 'attendance_models.dart';
import 'models.dart';

/// Monthly attendance, for the employee's own record.
class AttendanceApi {
  AttendanceApi(this.client);

  final ApiClient client;

  /// One month of day-by-day attendance plus its totals.
  ///
  /// `attendance/summary` is the right endpoint — it returns both halves in a
  /// single call. If a deployment has not got it, [history] covers the rows so
  /// the screen still works with totals derived locally.
  Future<MonthAttendance> month(DateTime when) async {
    final month = monthKey(when);

    try {
      final json = await client.get('attendance/summary', query: {
        'month': month,
      });
      final parsed = _parse(json);
      if (parsed.days.isNotEmpty) return parsed;
    } on ApiException {
      // Fall through to history rather than showing an error for a month that
      // simply has no summary.
    }

    return history(when);
  }

  Future<MonthAttendance> history(DateTime when) async {
    final json = await client.get('attendance/history', query: {
      'month': monthKey(when),
      'per_page': 31,
    });
    return _parse(json);
  }

  MonthAttendance _parse(Map<String, dynamic> json) {
    final data = payloadOf(json);

    final rows = <Map<String, dynamic>>[
      ...listOf(json, 'days'),
      if (listOf(json, 'days').isEmpty) ...listOf(json, 'records'),
    ];
    final source = rows.isNotEmpty ? rows : listOf(json);

    // The summary pads out the whole calendar month, so the current month
    // arrives with a tail of dates that have not happened yet. Listing them
    // would open the screen on an empty 30th and bury today below a week of
    // blank rows. Past months lose nothing — every date is already behind us.
    final today = DateTime.now();
    final cutoff = DateTime(today.year, today.month, today.day);

    final days = source
        .map(AttendanceDay.fromJson)
        .where((d) => !_dayOf(d.date).isAfter(cutoff))
        .toList()
      // Newest first: the day you care about is today.
      ..sort((a, b) => b.date.compareTo(a.date));

    final rawStats = data['stats'] ?? data['summary'] ?? data['totals'];
    final stats = rawStats is Map<String, dynamic>
        ? MonthStats.fromJson(rawStats)
        : MonthStats.fromDays(days);

    return MonthAttendance(days: days, stats: stats);
  }

  /// Date without its time, so comparisons are per-day rather than per-instant.
  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  static String monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}';
}
