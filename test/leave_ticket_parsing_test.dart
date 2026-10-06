import 'package:flutter_test/flutter_test.dart';

import 'package:attendence/data/leave_models.dart';
import 'package:attendence/data/ticket_models.dart';

void main() {
  group('LeaveApplication.fromJson', () {
    test('maps a pending request and keeps it cancellable', () {
      final leave = LeaveApplication.fromJson({
        'id': 41,
        'leave_type_name': 'Casual Leave',
        'start_date': '2026-09-24',
        'end_date': '2026-09-26',
        'reason': 'Family function',
        'status': 'pending',
      });

      expect(leave.id, '41');
      expect(leave.typeName, 'Casual Leave');
      expect(leave.days, 3);
      expect(leave.status, LeaveStatus.pending);
      expect(leave.statusLabel, 'Pending');
      expect(leave.isCancellable, isTrue);
    });

    test('an approved request cannot be cancelled from the app', () {
      final leave = LeaveApplication.fromJson({
        'id': 7,
        'type': 'SL',
        'from_date': '2026-09-01',
        'to_date': '2026-09-01',
        'status': 'APPROVED',
        'admin_remarks': 'Approved by HR',
      });

      expect(leave.status, LeaveStatus.approved);
      expect(leave.days, 1);
      expect(leave.remarks, 'Approved by HR');
      expect(leave.isCancellable, isFalse);
    });

    test('an explicit day count wins over the date span', () {
      final leave = LeaveApplication.fromJson({
        'id': 9,
        'start_date': '2026-09-24',
        'end_date': '2026-09-25',
        'days': 1.5,
        'status': 'pending',
      });

      expect(leave.days, 1.5);
    });
  });

  group('LeaveBalance.fromJson', () {
    test('derives the balance when the server omits it', () {
      final b = LeaveBalance.fromJson({
        'name': 'Earned Leave',
        'allowed': 12,
        'used': 4,
      });

      expect(b.balance, 8);
    });

    test('uses the balance the server sends', () {
      final b = LeaveBalance.fromJson({
        'name': 'Earned Leave',
        'allowed': 12,
        'used': 4,
        'balance': 7.5,
      });

      expect(b.balance, 7.5);
    });
  });

  group('Ticket.fromJson', () {
    test('maps a resolved ticket and its permission flags', () {
      final t = Ticket.fromJson({
        'id': 12,
        'reference': 'TKT-0012',
        'subject': 'Printer not responding',
        'body': 'Jams on every print.',
        'location': 'Kolkata HO',
        'status': 'resolved',
        'priority': 'high',
        'assigned_to_name': 'IT Desk',
        'created_at': '2026-09-18 10:22:00',
        'can_reply': true,
        'can_acknowledge': 1,
        'can_reraise': '1',
        'can_update': false,
      });

      expect(t.reference, 'TKT-0012');
      expect(t.status, TicketStatus.resolved);
      expect(t.statusLabel, 'Resolved');
      expect(t.priorityLabel, 'High');
      expect(t.assignedTo, 'IT Desk');
      expect(t.createdAt, DateTime(2026, 9, 18, 10, 22));
      expect(t.canReply, isTrue);
      expect(t.canAcknowledge, isTrue);
      expect(t.canReraise, isTrue);
      expect(t.canUpdate, isFalse);
    });

    test('in_progress arrives in several spellings', () {
      for (final raw in ['in_progress', 'In Progress', 'in-progress']) {
        expect(ticketStatusFrom(raw), TicketStatus.inProgress, reason: raw);
      }
    });

    test('falls back to an id reference and stays safe when fields are absent',
        () {
      final t = Ticket.fromJson({'id': 3});

      expect(t.reference, '#3');
      expect(t.subject, '(no subject)');
      expect(t.status, TicketStatus.open);
      // No flags means no buttons — never assume permission.
      expect(t.canReply, isFalse);
      expect(t.canAcknowledge, isFalse);
      expect(t.canReraise, isFalse);
    });
  });

  group('TicketReply.fromJson', () {
    test('marks internal notes', () {
      final r = TicketReply.fromJson({
        'id': 5,
        'user_name': 'IT Desk',
        'message': 'Cartridge replaced.',
        'created_at': '2026-09-19 11:00:00',
        'is_internal': 1,
      });

      expect(r.author, 'IT Desk');
      expect(r.isInternal, isTrue);
      expect(r.at, DateTime(2026, 9, 19, 11));
    });
  });
}
