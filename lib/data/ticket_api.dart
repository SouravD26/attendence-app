import 'api_client.dart';
import 'ticket_models.dart';

/// `tickets/*` endpoints.
///
/// Employees only need list / show / create / reply / acknowledge / reraise;
/// [update] is here for IT and Super Admin accounts signing in on the same app.
class TicketApi {
  TicketApi(this.client);

  final ApiClient client;

  /// Returns the tickets plus the per-status counts the list header shows.
  Future<({List<Ticket> tickets, Map<String, int> counts})> list({
    String? status,
    String? search,
    String? assigned,
    int page = 1,
    int perPage = 20,
  }) async {
    final json = await client.get('tickets', query: {
      if (status != null && status != 'all') 'status': status,
      // 'me' = assigned to me, 'raised' = raised by me, 'unassigned' = free.
      if (assigned != null && assigned.isNotEmpty) 'assigned': assigned,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      'page': page,
      'per_page': perPage,
    });

    final data = payloadOf(json);
    final counts = <String, int>{};
    final raw = data['counts'] ?? data['status_counts'] ?? json['counts'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final n = v is num ? v.toInt() : int.tryParse('$v');
        if (n != null) counts['$k'] = n;
      });
    }

    return (
      tickets: listOf(json, 'tickets').map(Ticket.fromJson).toList(),
      counts: counts,
    );
  }

  Future<TicketDetail> show(String id) async {
    final json = await client.get('tickets/show', query: {'id': id});
    final data = payloadOf(json);

    final raw = data['ticket'];
    final ticket = Ticket.fromJson(
      raw is Map<String, dynamic> ? raw : data,
    );

    return TicketDetail(
      ticket: ticket,
      replies: listOf(data, 'replies').map(TicketReply.fromJson).toList(),
      activity: listOf(data, 'activity').map(TicketActivity.fromJson).toList(),
      attachments:
          listOf(data, 'attachments').map(TicketAttachment.fromJson).toList(),
    );
  }

  Future<void> create({
    required String subject,
    required String body,
    required String location,
    required bool trainedBefore,
    List<String> photos = const [],
  }) =>
      client.post('tickets/create', body: {
        'subject': subject,
        'body': body,
        'location': location,
        'trained_before': trainedBefore ? 'yes' : 'no',
        // Base64 data URIs, the same form the attendance selfie takes.
        if (photos.isNotEmpty) 'photos': photos,
      });

  Future<void> reply(
    String id,
    String message, {
    bool internal = false,
    List<String> photos = const [],
  }) =>
      client.post('tickets/reply', body: {
        'id': id,
        'message': message,
        if (internal) 'is_internal': 1,
        if (photos.isNotEmpty) 'photos': photos,
      });

  Future<void> acknowledge(String id) =>
      client.post('tickets/acknowledge', body: {'id': id});

  Future<void> reraise(String id, {String? reason}) =>
      client.post('tickets/reraise', body: {
        'id': id,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });

  Future<void> update(
    String id, {
    String? status,
    String? priority,
    String? assignedTo,
    String? departmentId,
  }) =>
      client.post('tickets/update', body: {
        'id': id,
        if (status != null) 'status': status,
        if (priority != null) 'priority': priority,
        if (assignedTo != null) 'assigned_to': assignedTo,
        if (departmentId != null) 'department_id': departmentId,
      });

  /// The role-appropriate queue plus headline counts, in one call.
  Future<TicketDashboard> dashboard() async {
    final json = await client.get('tickets/dashboard');
    final data = payloadOf(json);

    final counts = <String, int>{};
    final raw = data['counts'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final n = v is num ? v.toInt() : int.tryParse('$v');
        if (n != null) counts['$k'] = n;
      });
    }

    final queue = data['queue'];
    return TicketDashboard(
      queueTitle: queue is Map ? '${queue['title'] ?? ''}' : '',
      queue: queue is Map
          ? listOf(queue as Map<String, dynamic>, 'tickets')
              .map(Ticket.fromJson)
              .toList()
          : const [],
      recent: listOf(data, 'recent').map(Ticket.fromJson).toList(),
      counts: counts,
      canAssign: data['can_assign'] == true,
      canWork: data['can_work'] == true,
    );
  }

  /// Assignment has its own endpoint: Super Admin only, and 0 unassigns.
  Future<void> assign(String id, {String? assignedTo, String? priority}) =>
      client.post('tickets/assign', body: {
        'id': id,
        'assigned_to': assignedTo ?? '0',
        if (priority != null) 'priority': priority,
      });

  /// The work log, plus its total and whether this caller may add to it.
  /// The rows sit under `entries`, not at the top level.
  Future<({List<WorkLogEntry> entries, double totalHours, bool canAdd})>
      workLog(String id) async {
    final json = await client.get('tickets/worklog', query: {'id': id});
    final data = payloadOf(json);
    final total = data['total_hours'];

    return (
      entries: listOf(data, 'entries').map(WorkLogEntry.fromJson).toList(),
      totalHours: total is num
          ? total.toDouble()
          : double.tryParse('${total ?? 0}') ?? 0,
      canAdd: data['can_add'] == true,
    );
  }

  Future<void> logWork(
    String id, {
    required String summary,
    DateTime? workDate,
    double? hours,
    String? details,
  }) =>
      client.post('tickets/log_work', body: {
        'id': id,
        'summary': summary,
        if (workDate != null)
          'work_date': '${workDate.year.toString().padLeft(4, '0')}-'
              '${workDate.month.toString().padLeft(2, '0')}-'
              '${workDate.day.toString().padLeft(2, '0')}',
        if (hours != null) 'hours': hours,
        if (details != null && details.trim().isNotEmpty) 'details': details,
      });

  /// The people a ticket may be assigned to. Super Admin / IT only.
  Future<List<ItStaff>> itStaff() async {
    final json = await client.get('tickets/it_staff');
    return listOf(json).map(ItStaff.fromJson).toList();
  }

  Future<TicketFormOptions> formOptions() async {
    final json = await client.get('tickets/locations');
    final data = payloadOf(json);
    return TicketFormOptions(
      locations: _strings(data, ['locations', 'location', 'data']),
      statuses: _strings(data, ['statuses', 'status']),
      priorities: _strings(data, ['priorities', 'priority']),
    );
  }

  /// The lists may arrive as bare strings or as {id, name} objects.
  static List<String> _strings(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v is! List) continue;
      return v
          .map((e) {
            if (e is Map) {
              return '${e['name'] ?? e['label'] ?? e['title'] ?? e['value'] ?? ''}';
            }
            return '$e';
          })
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const [];
  }
}
