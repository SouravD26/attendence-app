// Leave domain models, mapped from the `leave/*` endpoints.
//
// Same alias-tolerant approach as models.dart: the HRMS payloads name a few
// fields differently between endpoints, so `pick` resolves them.

import 'api_client.dart';
import 'models.dart';

class LeaveType {
  final String code;
  final String name;
  final double? allowance;

  const LeaveType({required this.code, required this.name, this.allowance});

  factory LeaveType.fromJson(Map<String, dynamic> json) => LeaveType(
        code: '${pick(json, ['code', 'leave_type', 'type', 'id', 'slug']) ?? ''}',
        name: '${pick(json, ['name', 'label', 'title', 'leave_name', 'leave_type']) ?? ''}',
        allowance: _num(pick(json, [
          'days_allowed',
          'allowance',
          'allowed',
          'yearly_allowance',
          'total',
        ])),
      );
}

class LeaveBalance {
  final String code;
  final String name;
  final double allowed;
  final double used;
  final double balance;

  const LeaveBalance({
    required this.code,
    required this.name,
    required this.allowed,
    required this.used,
    required this.balance,
  });

  factory LeaveBalance.fromJson(Map<String, dynamic> json) {
    // The API names these days_allowed / days_used / days_balance.
    final allowed =
        _num(pick(json, ['days_allowed', 'allowed', 'allowance', 'total'])) ?? 0;
    final used = _num(pick(json, ['days_used', 'used', 'taken', 'consumed'])) ?? 0;
    return LeaveBalance(
      code: '${pick(json, ['code', 'leave_type', 'type', 'id']) ?? ''}',
      name: '${pick(json, [
            'name',
            'label',
            'title',
            'leave_name',
            'leave_type',
          ]) ?? ''}',
      allowed: allowed,
      used: used,
      // Servers that omit the balance still give us enough to derive it.
      balance: _num(pick(json, [
            'days_balance',
            'balance',
            'remaining',
            'available',
          ])) ??
          (allowed - used),
    );
  }
}

enum LeaveStatus { pending, approved, rejected, cancelled, unknown }

LeaveStatus leaveStatusFrom(Object? raw) {
  switch ('${raw ?? ''}'.trim().toLowerCase()) {
    case 'pending':
    case 'applied':
    case 'awaiting':
      return LeaveStatus.pending;
    case 'approved':
    case 'accept':
    case 'accepted':
      return LeaveStatus.approved;
    case 'rejected':
    case 'declined':
      return LeaveStatus.rejected;
    case 'cancelled':
    case 'canceled':
      return LeaveStatus.cancelled;
    default:
      return LeaveStatus.unknown;
  }
}

class LeaveApplication {
  final String id;
  final String typeName;
  final DateTime? from;
  final DateTime? to;
  final double days;
  final String reason;
  final LeaveStatus status;
  final String statusLabel;
  final String? remarks;
  final DateTime? appliedOn;

  const LeaveApplication({
    required this.id,
    required this.typeName,
    required this.from,
    required this.to,
    required this.days,
    required this.reason,
    required this.status,
    required this.statusLabel,
    this.remarks,
    this.appliedOn,
  });

  bool get isCancellable => status == LeaveStatus.pending;

  factory LeaveApplication.fromJson(Map<String, dynamic> json) {
    final rawStatus = pick(json, ['status', 'state', 'approval_status']);
    final from = parseDate(pick(json, ['start_date', 'from_date', 'from', 'date_from']));
    final to = parseDate(pick(json, ['end_date', 'to_date', 'to', 'date_to']));

    return LeaveApplication(
      id: '${pick(json, ['id', 'leave_id', 'application_id']) ?? ''}',
      typeName: '${pick(json, [
            'leave_type_name',
            'type_name',
            'leave_type',
            'type',
            'name',
          ]) ?? 'Leave'}',
      from: from,
      to: to,
      days: _num(pick(json, ['days', 'total_days', 'no_of_days'])) ??
          _spanDays(from, to),
      reason: '${pick(json, ['reason', 'remark', 'purpose', 'description']) ?? ''}',
      status: leaveStatusFrom(rawStatus),
      statusLabel: _title('${rawStatus ?? 'Pending'}'),
      remarks: pick(json, [
        'admin_remarks',
        'approver_remarks',
        'notes',
        'action_notes',
      ])?.toString(),
      appliedOn: parseDate(pick(json, ['applied_on', 'created_at', 'applied_at'])),
    );
  }
}

/// A day marked on duty or as comp-off — both endpoints return the same shape.
class DutyRecord {
  final DateTime? date;
  final String label;
  final String? note;

  const DutyRecord({required this.date, required this.label, this.note});

  factory DutyRecord.fromJson(Map<String, dynamic> json, String fallback) =>
      DutyRecord(
        date: parseDate(pick(json, [
          'date',
          'od_date',
          'comp_off_date',
          'leave_date',
        ])),
        label: '${pick(json, ['status', 'type', 'title']) ?? fallback}',
        note: pick(json, ['reason', 'remarks', 'earned_date', 'note'])
            ?.toString(),
      );
}

double? _num(Object? v) =>
    v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

double _spanDays(DateTime? from, DateTime? to) {
  if (from == null) return 0;
  if (to == null) return 1;
  return to.difference(from).inDays + 1.0;
}

String _title(String s) {
  final t = s.trim();
  if (t.isEmpty) return 'Pending';
  return t[0].toUpperCase() + t.substring(1).toLowerCase();
}
