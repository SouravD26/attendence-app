import 'package:flutter_test/flutter_test.dart';

import 'package:attendence/data/api_client.dart';
import 'package:attendence/data/models.dart';

void main() {
  group('parseDateTime', () {
    test('reads a full timestamp', () {
      final d = parseDateTime('2026-09-12 09:28:15');
      expect(d, DateTime(2026, 9, 12, 9, 28, 15));
    });

    test('reads a bare time against the record date', () {
      final d = parseDateTime('09:28:15', onDate: DateTime(2026, 9, 12));
      expect(d, DateTime(2026, 9, 12, 9, 28, 15));
    });

    test('treats empty, null-ish and 00:00:00 as not punched', () {
      expect(parseDateTime(null), isNull);
      expect(parseDateTime(''), isNull);
      expect(parseDateTime('null'), isNull);
      expect(parseDateTime('00:00:00'), isNull);
    });
  });

  group('DayStatus.fromJson', () {
    test('maps a completed day and computes hours worked', () {
      final day = DayStatus.fromJson({
        'date': '2026-09-12',
        'punch_in': '09:30:00',
        'punch_out': '18:30:00',
        'punch_in_address': 'Sanmarg House',
      });

      expect(day.isComplete, isTrue);
      expect(day.isCheckedIn, isFalse);
      expect(day.workedAt(DateTime.now()), const Duration(hours: 9));
      expect(day.location, 'Sanmarg House');
    });

    test('an open punch is still counting', () {
      final day = DayStatus.fromJson({
        'date': '2026-09-12',
        'check_in': '2026-09-12 09:00:00',
      });

      expect(day.isCheckedIn, isTrue);
      expect(
        day.workedAt(DateTime(2026, 9, 12, 13, 30)),
        const Duration(hours: 4, minutes: 30),
      );
      expect(day.progressAt(DateTime(2026, 9, 12, 13, 30)), closeTo(0.5, 0.01));
    });

    test('progress never exceeds a full ring on overtime', () {
      final day = DayStatus.fromJson({
        'date': '2026-09-12',
        'punch_in': '08:00:00',
      });
      expect(day.progressAt(DateTime(2026, 9, 12, 23, 0)), 1.0);
    });

    test('an empty record means nobody has punched in yet', () {
      final day = DayStatus.fromJson({'date': '2026-09-12'});
      expect(day.checkIn, isNull);
      expect(day.workedAt(DateTime.now()), Duration.zero);
    });

    group('the real attendance/today summary', () {
      // Regression coverage for the punch button getting stuck disabled:
      // this endpoint allows more than one punch in/out pair per day, so a
      // closed session must never permanently lock the day the way the
      // legacy single-record shape does.
      test('a fresh day with no punches is not checked in and not locked', () {
        final day = DayStatus.fromJson({
          'date': '2026-09-24',
          'server_time': '2026-09-24 11:00:00',
          'is_punched_in': false,
          'open_punch': null,
          'can_punch_in': true,
          'can_punch_out': false,
          'worked_minutes': 0,
          'first_punch_in': null,
          'last_punch_out': null,
        });

        expect(day.isCheckedIn, isFalse);
        expect(day.isComplete, isFalse);
        expect(day.checkIn, isNull);
      });

      test('a closed session today does not lock out punching in again', () {
        final day = DayStatus.fromJson({
          'date': '2026-09-24',
          'is_punched_in': false,
          'open_punch': null,
          'can_punch_in': true,
          'can_punch_out': false,
          'worked_minutes': 540,
          'first_punch_in': '09:30:00',
          'last_punch_out': '18:30:00',
        });

        expect(day.isCheckedIn, isFalse);
        expect(day.isComplete, isFalse);
        expect(day.workedAt(DateTime.now()), const Duration(hours: 9));
      });

      test('an open punch counts live from its own start time', () {
        final day = DayStatus.fromJson({
          'date': '2026-09-24',
          'is_punched_in': true,
          'open_punch': {'punch_in': '09:00:00'},
          'can_punch_in': false,
          'can_punch_out': true,
          'worked_minutes': 0,
          'first_punch_in': '09:00:00',
          'last_punch_out': null,
        });

        expect(day.isCheckedIn, isTrue);
        expect(day.checkIn, DateTime(2026, 9, 24, 9, 0, 0));
        expect(
          day.workedAt(DateTime(2026, 9, 24, 13, 30)),
          const Duration(hours: 4, minutes: 30),
        );
      });
    });
  });

  group('Employee.fromJson', () {
    test('accepts the field aliases the endpoints use', () {
      final e = Employee.fromJson({
        'user_id': 42,
        'full_name': 'A. Employee',
        'designation': 'Executive',
        'department_name': 'Operations',
        'mobile': '9800000000',
      });

      expect(e.id, '42');
      expect(e.name, 'A. Employee');
      expect(e.department, 'Operations');
      expect(e.phone, '9800000000');
      expect(e.isAdmin, isFalse);
    });

    test('detects admins from either flag or role', () {
      expect(Employee.fromJson({'is_admin': 1}).isAdmin, isTrue);
      expect(Employee.fromJson({'role': 'HR'}).isAdmin, isTrue);
      expect(Employee.fromJson({'role': 'employee'}).isAdmin, isFalse);
    });
  });

  group('response unwrapping', () {
    test('payloadOf handles wrapped and bare bodies', () {
      expect(payloadOf({'success': true, 'data': {'id': 1}}), {'id': 1});
      expect(payloadOf({'id': 1}), {'id': 1});
    });

    test('listOf finds the array wherever it is', () {
      expect(listOf({'data': [{'id': 1}]}).length, 1);
      expect(listOf({'items': [{'id': 1}, {'id': 2}]}).length, 2);
      expect(listOf({'data': {'items': [{'id': 1}]}}).length, 1);
      expect(listOf({'message': 'none'}), isEmpty);
    });

    test('pick skips nulls and empty strings', () {
      expect(pick({'a': null, 'b': '', 'c': 'x'}, ['a', 'b', 'c']), 'x');
      expect(pick({}, ['a']), isNull);
    });
  });
}
