import 'package:flutter_test/flutter_test.dart';

import 'package:attendence/data/attendance_models.dart';

void main() {
  group('parseDuration', () {
    test('reads clock strings', () {
      expect(parseDuration('08:30'), const Duration(hours: 8, minutes: 30));
      expect(
        parseDuration('9:05:30'),
        const Duration(hours: 9, minutes: 5, seconds: 30),
      );
      // Monthly totals run past 24 hours.
      expect(parseDuration('150:34'), const Duration(hours: 150, minutes: 34));
    });

    test('reads decimal hours', () {
      expect(parseDuration(8.5), const Duration(hours: 8, minutes: 30));
      expect(parseDuration('7.25'), const Duration(hours: 7, minutes: 15));
      expect(parseDuration(9), const Duration(hours: 9));
    });

    test('treats nothing and nonsense as no value', () {
      expect(parseDuration(null), isNull);
      expect(parseDuration(''), isNull);
      expect(parseDuration('not a time'), isNull);
      expect(parseDuration(0), Duration.zero);
      expect(parseDuration(-3), Duration.zero);
    });
  });

  group('AttendanceDay.fromJson', () {
    test('maps a complete day', () {
      final day = AttendanceDay.fromJson({
        'date': '2026-09-18',
        'punch_in': '09:28:00',
        'punch_out': '18:42:00',
        'status': 'present',
      });

      expect(day.date, DateTime(2026, 9, 18));
      expect(day.punchIn, DateTime(2026, 9, 18, 9, 28));
      expect(day.punchOut, DateTime(2026, 9, 18, 18, 42));
      expect(day.worked, const Duration(hours: 9, minutes: 14));
      expect(day.mark, DayMark.present);
      expect(day.isOpen, isFalse);
    });

    test('a night shift closing after midnight is not negative', () {
      final day = AttendanceDay.fromJson({
        'date': '2026-09-20',
        'punch_in': '21:19:00',
        'punch_out': '06:03:00',
      });

      expect(day.worked, const Duration(hours: 8, minutes: 44));
      expect(day.worked.isNegative, isFalse);
    });

    test('a missing punch out is flagged as open', () {
      final day = AttendanceDay.fromJson({
        'date': '2026-09-19',
        'punch_in': '10:11:00',
      });

      expect(day.isOpen, isTrue);
      expect(day.worked, Duration.zero);
    });

    test("the server's own total wins over the punch pair", () {
      final day = AttendanceDay.fromJson({
        'date': '2026-09-18',
        'punch_in': '09:00:00',
        'punch_out': '19:00:00',
        // Shift rules deducted a break; trust the server.
        'worked_hours': '9:00',
      });

      expect(day.worked, const Duration(hours: 9));
    });

    test('status spellings fold to one mark', () {
      expect(dayStatusFrom('P'), DayMark.present);
      expect(dayStatusFrom('half-day'), DayMark.halfDay);
      expect(dayStatusFrom('WEEK OFF'), DayMark.weekOff);
      expect(dayStatusFrom('od'), DayMark.onDuty);
      expect(dayStatusFrom('something else'), DayMark.unknown);
    });
  });

  group('MonthStats.fromDays', () {
    test('counts marks and sums hours', () {
      final stats = MonthStats.fromDays([
        AttendanceDay.fromJson({
          'date': '2026-09-01',
          'status': 'present',
          'worked_hours': '9:00',
        }),
        AttendanceDay.fromJson({
          'date': '2026-09-02',
          'status': 'present',
          'worked_hours': '8:30',
        }),
        AttendanceDay.fromJson({'date': '2026-09-03', 'status': 'absent'}),
        AttendanceDay.fromJson({'date': '2026-09-04', 'status': 'leave'}),
      ]);

      expect(stats.present, 2);
      expect(stats.absent, 1);
      expect(stats.leave, 1);
      expect(stats.totalWorked, const Duration(hours: 17, minutes: 30));
    });

    test('an unmarked day that has a punch still counts as present', () {
      final stats = MonthStats.fromDays([
        AttendanceDay.fromJson({
          'date': '2026-09-05',
          'punch_in': '09:30:00',
          'punch_out': '18:00:00',
        }),
      ]);

      expect(stats.present, 1);
    });
  });

  group('real attendance/summary payload', () {
    // Shapes captured from a live call, not from the endpoint docs.
    test('a summary day is typed by `type`, not `status`', () {
      final day = AttendanceDay.fromJson({
        'date': '2026-09-02',
        'day': 'Wednesday',
        'type': 'Present',
        'leave_type': null,
        'punch_in': '20:31:33',
        'punch_out': '05:08:17',
        'punch_count': 1,
        'incomplete': false,
        'worked_minutes': 517,
        'worked_hours': '08:37',
      });

      expect(day.mark, DayMark.present);
      expect(day.worked, const Duration(hours: 8, minutes: 37));
      expect(day.isOpen, isFalse);
    });

    test('worked_minutes is read as minutes, never as hours', () {
      final day = AttendanceDay.fromJson({
        'date': '2026-09-02',
        'worked_minutes': 517,
      });

      expect(day.worked, const Duration(minutes: 517));
      expect(day.worked.inHours, 8);
    });

    test('an absent day carries no punches', () {
      final day = AttendanceDay.fromJson({
        'date': '2026-09-01',
        'type': 'Absent',
        'punch_in': null,
        'punch_out': null,
        'worked_minutes': 0,
      });

      expect(day.mark, DayMark.absent);
      expect(day.punchIn, isNull);
      expect(day.worked, Duration.zero);
    });

    test("the server's incomplete flag marks an open day", () {
      final day = AttendanceDay.fromJson({
        'date': '2026-09-15',
        'type': 'Present',
        'punch_in': '10:11:00',
        'punch_out': '19:26:00',
        'incomplete': true,
      });

      expect(day.isOpen, isTrue);
    });

    test('the hyphenated and spaced types the API sends', () {
      expect(dayStatusFrom('Week off'), DayMark.weekOff);
      expect(dayStatusFrom('Comp-off'), DayMark.compOff);
      expect(dayStatusFrom('OD'), DayMark.onDuty);
    });

    test('location comes from punch_in_location', () {
      final day = AttendanceDay.fromJson({
        'date': '2026-09-20',
        'punch_in_location': 'Maa Flyover, Park Circus, Kolkata',
      });

      expect(day.location, 'Maa Flyover, Park Circus, Kolkata');
    });

    test('the real stats block maps whole', () {
      final stats = MonthStats.fromJson({
        'present': 15,
        'absent': 5,
        'leave': 0,
        'od': 0,
        'comp_off': 0,
        'holiday': 0,
        'week_off': 2,
        'worked_minutes': 7779,
        'incomplete': 6,
        'payable_days': 17,
        'worked_hours': '129:39',
      });

      expect(stats.present, 15);
      expect(stats.absent, 5);
      expect(stats.weekOff, 2);
      expect(stats.incomplete, 6);
      expect(stats.payableDays, 17);
      // 7779 minutes is 129:39 — the two fields agree, and minutes win.
      expect(stats.totalWorked, const Duration(minutes: 7779));
      expect(formatWorked(stats.totalWorked), '129h 39m');
    });
  });

  group('multi-punch days', () {
    // The 19th in the live data: one shift left open, plus an 18-second punch.
    // The day-level in/out therefore straddle two different pairs.
    test('a day whose punches do not pair up is still flagged open', () {
      final day = AttendanceDay.fromJson({
        'date': '2026-09-19',
        'type': 'Present',
        'punch_in': '11:04:16',
        'punch_out': '20:34:47',
        'punch_count': 2,
        'incomplete': true,
        'worked_minutes': 0,
      });

      expect(day.punchCount, 2);
      expect(day.isOpen, isTrue);
      // Both times exist, but nothing was actually worked to completion.
      expect(day.punchIn, isNotNull);
      expect(day.punchOut, isNotNull);
      expect(day.worked, Duration.zero);
    });

    test('a single clean punch is not flagged', () {
      final day = AttendanceDay.fromJson({
        'date': '2026-09-02',
        'type': 'Present',
        'punch_in': '20:31:33',
        'punch_out': '05:08:17',
        'punch_count': 1,
        'incomplete': false,
        'worked_minutes': 517,
      });

      expect(day.punchCount, 1);
      expect(day.isOpen, isFalse);
    });

    test('a day with no punches reports a count of zero', () {
      final day = AttendanceDay.fromJson({
        'date': '2026-09-22',
        'type': 'Absent',
        'punch_count': 0,
        'incomplete': false,
      });

      expect(day.punchCount, 0);
      expect(day.isOpen, isFalse);
    });
  });

  group('formatWorked', () {
    test('formats hours and minutes, and marks nothing worked', () {
      expect(formatWorked(const Duration(hours: 9, minutes: 5)), '9h 05m');
      expect(formatWorked(const Duration(hours: 150, minutes: 34)), '150h 34m');
      expect(formatWorked(Duration.zero), '—');
    });
  });
}
