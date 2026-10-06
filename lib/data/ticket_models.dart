// Ticket domain models, mapped from the `tickets/*` endpoints.
//
// The API sends per-caller permission flags (can_reply / can_acknowledge /
// can_reraise / can_update) so the app draws the right buttons without
// re-implementing the server's role rules.

import 'api_client.dart';
import 'models.dart';

enum TicketStatus { open, assigned, inProgress, resolved, closed, reopened, unknown }

TicketStatus ticketStatusFrom(Object? raw) {
  final s = '${raw ?? ''}'.trim().toLowerCase().replaceAll(RegExp(r'[\s-]'), '_');
  switch (s) {
    case 'open':
    case 'new':
      return TicketStatus.open;
    case 'assigned':
      return TicketStatus.assigned;
    case 'in_progress':
    case 'inprogress':
    case 'working':
      return TicketStatus.inProgress;
    case 'resolved':
      return TicketStatus.resolved;
    case 'closed':
    case 'acknowledged':
      return TicketStatus.closed;
    case 'reopened':
    case 'reraised':
      return TicketStatus.reopened;
    default:
      return TicketStatus.unknown;
  }
}

class Ticket {
  final String id;
  final String reference;
  final String subject;
  final String body;
  final String location;
  final TicketStatus status;
  final String statusLabel;
  final String priorityLabel;
  final String? department;
  final String? assignedTo;

  /// Numeric id of the assignee, for "is this mine?" checks.
  final String? assignedToId;
  final String? raisedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int replyCount;

  final bool canReply;
  final bool canAcknowledge;
  final bool canReraise;
  final bool canUpdate;

  /// Only the Super Admin may assign or set priority; IT staff move status.
  final bool canAssign;

  /// The statuses this caller is allowed to set, straight from the server.
  final List<String> settableStatuses;

  const Ticket({
    required this.id,
    required this.reference,
    required this.subject,
    required this.body,
    required this.location,
    required this.status,
    required this.statusLabel,
    required this.priorityLabel,
    this.department,
    this.assignedTo,
    this.assignedToId,
    this.raisedBy,
    this.createdAt,
    this.updatedAt,
    this.replyCount = 0,
    this.canReply = false,
    this.canAcknowledge = false,
    this.canReraise = false,
    this.canUpdate = false,
    this.canAssign = false,
    this.settableStatuses = const [],
  });

  factory Ticket.fromJson(Map<String, dynamic> json) {
    // Default to open so the enum and the label never disagree — a ticket
    // with no status yet is a new one.
    final rawStatus = pick(json, ['status', 'state', 'ticket_status']) ?? 'open';
    final id = '${pick(json, ['id', 'ticket_id']) ?? ''}';
    return Ticket(
      id: id,
      reference:
          '${pick(json, ['reference', 'ticket_no', 'ticket_number', 'code']) ?? '#$id'}',
      subject: '${pick(json, ['subject', 'title', 'summary']) ?? '(no subject)'}',
      body: '${pick(json, ['body', 'description', 'message', 'details']) ?? ''}',
      location: '${pick(json, ['location', 'location_name', 'site']) ?? ''}',
      status: ticketStatusFrom(rawStatus),
      statusLabel: _title('$rawStatus'),
      priorityLabel: _title('${pick(json, ['priority', 'priority_label']) ?? 'Normal'}'),
      department:
          pick(json, ['department', 'department_name', 'dept'])?.toString(),
      // `agent_name` is what the API actually sends; without it the card fell
      // through to `assigned_to` and displayed a numeric id.
      assignedTo: pick(json, [
        'agent_name',
        'assigned_to_name',
        'assignee_name',
        'assigned_name',
      ])?.toString(),
      assignedToId: pick(json, ['assigned_to', 'assignee_id'])?.toString(),
      raisedBy: pick(json, [
        'raised_by_name',
        'requester_name',
        'user_name',
        'created_by_name',
      ])?.toString(),
      createdAt: parseDate(pick(json, ['created_at', 'raised_on', 'created'])),
      updatedAt: parseDate(pick(json, ['updated_at', 'last_activity_at', 'modified'])),
      replyCount:
          (_int(pick(json, ['reply_count', 'replies_count', 'comments'])) ?? 0),
      canReply: _flag(json['can_reply']),
      canAcknowledge: _flag(json['can_acknowledge']),
      canReraise: _flag(json['can_reraise']),
      canUpdate: _flag(json['can_update']),
      canAssign: _flag(json['can_assign']),
      settableStatuses: (json['settable_statuses'] is List)
          ? (json['settable_statuses'] as List).map((e) => '$e').toList()
          : const [],
    );
  }
}

class TicketReply {
  final String id;
  final String author;
  final String message;
  final DateTime? at;
  final bool isInternal;

  const TicketReply({
    required this.id,
    required this.author,
    required this.message,
    this.at,
    this.isInternal = false,
  });

  factory TicketReply.fromJson(Map<String, dynamic> json) => TicketReply(
        id: '${pick(json, ['id', 'reply_id']) ?? ''}',
        author: '${pick(json, [
              'author',
              'user_name',
              'name',
              'created_by_name',
              'by',
            ]) ?? 'Unknown'}',
        message: '${pick(json, ['message', 'body', 'reply', 'text']) ?? ''}',
        at: parseDate(pick(json, ['created_at', 'replied_at', 'at', 'date'])),
        isInternal: _flag(pick(json, ['is_internal', 'internal'])),
      );
}

class TicketActivity {
  final String text;
  final String? by;
  final DateTime? at;

  const TicketActivity({required this.text, this.by, this.at});

  factory TicketActivity.fromJson(Map<String, dynamic> json) => TicketActivity(
        text: '${pick(json, ['action', 'text', 'description', 'event', 'message']) ?? ''}',
        by: pick(json, ['by', 'user_name', 'name', 'actor'])?.toString(),
        at: parseDate(pick(json, ['created_at', 'at', 'date', 'time'])),
      );
}

/// A photo or file on a ticket. `url` is signed and expiring, so it can go
/// straight into an Image widget without a bearer header.
class TicketAttachment {
  final String id;
  final String name;
  final String? url;
  final String mime;
  final int sizeBytes;
  final String? replyId;

  const TicketAttachment({
    required this.id,
    required this.name,
    this.url,
    this.mime = '',
    this.sizeBytes = 0,
    this.replyId,
  });

  bool get isImage => mime.startsWith('image/');

  factory TicketAttachment.fromJson(Map<String, dynamic> json) =>
      TicketAttachment(
        id: '${pick(json, ['id', 'attachment_id']) ?? ''}',
        name: '${pick(json, ['name', 'original_name', 'filename']) ?? 'photo'}',
        url: pick(json, ['url', 'link', 'href'])?.toString(),
        mime: '${pick(json, ['mime', 'mime_type', 'type']) ?? ''}',
        sizeBytes: _int(pick(json, ['size_bytes', 'size'])) ?? 0,
        replyId: pick(json, ['reply_id'])?.toString(),
      );
}

/// `tickets/show` — the ticket plus its conversation and audit trail.
class TicketDetail {
  final Ticket ticket;
  final List<TicketReply> replies;
  final List<TicketActivity> activity;
  final List<TicketAttachment> attachments;

  const TicketDetail({
    required this.ticket,
    required this.replies,
    required this.activity,
    this.attachments = const [],
  });
}

/// One person a ticket may be assigned to, from `tickets/it_staff`.
class ItStaff {
  final String id;
  final String name;
  final String? department;
  final String? designation;

  const ItStaff({
    required this.id,
    required this.name,
    this.department,
    this.designation,
  });

  factory ItStaff.fromJson(Map<String, dynamic> json) => ItStaff(
        id: '${pick(json, ['id', 'user_id']) ?? ''}',
        name: '${pick(json, ['name', 'full_name']) ?? ''}',
        department: pick(json, ['department', 'dept'])?.toString(),
        designation: pick(json, ['designation', 'title'])?.toString(),
      );
}

/// `tickets/dashboard` — the queue that matters to this caller, already
/// chosen by the server: unassigned work for the Super Admin, "on your desk"
/// for IT, and "waiting for your acknowledgement" for everyone else.
class TicketDashboard {
  final String queueTitle;
  final List<Ticket> queue;
  final List<Ticket> recent;
  final Map<String, int> counts;
  final bool canAssign;
  final bool canWork;

  const TicketDashboard({
    this.queueTitle = '',
    this.queue = const [],
    this.recent = const [],
    this.counts = const {},
    this.canAssign = false,
    this.canWork = false,
  });

  static const empty = TicketDashboard();

  int get open => counts['open'] ?? 0;
  int get pending => counts['pending'] ?? 0;
  int get resolved => counts['resolved'] ?? 0;
  int get highOpen => counts['high_open'] ?? 0;
}

/// One entry in a ticket's work log.
class WorkLogEntry {
  final String id;
  final String summary;
  final String? details;
  final DateTime? workDate;
  final double hours;
  final String? by;

  const WorkLogEntry({
    required this.id,
    required this.summary,
    this.details,
    this.workDate,
    this.hours = 0,
    this.by,
  });

  factory WorkLogEntry.fromJson(Map<String, dynamic> json) => WorkLogEntry(
        id: '${pick(json, ['id', 'log_id']) ?? ''}',
        summary: '${pick(json, ['summary', 'title']) ?? ''}',
        details: pick(json, ['details', 'note', 'body'])?.toString(),
        workDate: parseDate(pick(json, ['work_date', 'date'])),
        hours: _hours(pick(json, ['hours', 'time_spent'])),
        by: pick(json, ['author', 'user_name', 'name', 'by'])?.toString(),
      );

  static double _hours(Object? v) => v == null
      ? 0
      : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
}

/// `tickets/locations` — everything the create form needs.
class TicketFormOptions {
  final List<String> locations;
  final List<String> statuses;
  final List<String> priorities;

  const TicketFormOptions({
    this.locations = const [],
    this.statuses = const [],
    this.priorities = const [],
  });
}

bool _flag(Object? v) => v == true || v == 1 || v == '1' || v == 'yes';

int? _int(Object? v) =>
    v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));

String _title(String s) {
  final t = s.trim().replaceAll('_', ' ');
  if (t.isEmpty) return '—';
  return t
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}
