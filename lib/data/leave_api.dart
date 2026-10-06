import 'api_client.dart';
import 'leave_models.dart';

/// `leave/*` endpoints. Thin — parsing lives in the models.
class LeaveApi {
  LeaveApi(this.client);

  final ApiClient client;

  Future<List<LeaveType>> types() async {
    final json = await client.get('leave/types');
    return listOf(json, 'types').map(LeaveType.fromJson).toList();
  }

  Future<List<LeaveBalance>> balance({int? year}) async {
    final json = await client.get('leave/balance', query: {'year': year});
    // The payload nests the rows under `balances`.
    return listOf(json, 'balances').map(LeaveBalance.fromJson).toList();
  }

  Future<List<LeaveApplication>> list({String? status, int page = 1}) async {
    final json = await client.get('leave/list', query: {
      if (status != null && status != 'all') 'status': status,
      'page': page,
    });
    return listOf(json, 'leaves').map(LeaveApplication.fromJson).toList();
  }

  Future<void> apply({
    required String leaveType,
    required DateTime start,
    required DateTime end,
    required String reason,
  }) =>
      client.post('leave/apply', body: {
        'leave_type': leaveType,
        'start_date': _d(start),
        'end_date': _d(end),
        'reason': reason,
      });

  Future<void> cancel(String id) => client.post('leave/cancel', body: {'id': id});

  Future<List<DutyRecord>> onDuty({DateTime? from, DateTime? to}) =>
      _duty('leave/od', 'On duty', from, to);

  Future<List<DutyRecord>> compOff({DateTime? from, DateTime? to}) =>
      _duty('leave/comp_off', 'Comp off', from, to);

  Future<List<DutyRecord>> _duty(
    String path,
    String fallback,
    DateTime? from,
    DateTime? to,
  ) async {
    final json = await client.get(path, query: {
      if (from != null) 'from': _d(from),
      if (to != null) 'to': _d(to),
    });
    return listOf(json)
        .map((r) => DutyRecord.fromJson(r, fallback))
        .toList();
  }

  static String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
