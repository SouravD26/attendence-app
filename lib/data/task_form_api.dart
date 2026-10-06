import 'api_client.dart';
import 'task_form_models.dart';

/// `forms/*` endpoints — the department's daily-task Google Form.
class TaskFormApi {
  TaskFormApi(this.client);

  final ApiClient client;

  Future<TaskFormInfo> fetch() async {
    final json = await client.get('forms');
    return TaskFormInfo.fromJson(payloadOf(json));
  }

  /// [answers] maps field key -> string, or list of strings for checkboxes.
  /// Returns the server's confirmation message.
  Future<String> submit(Map<String, Object> answers) async {
    final json = await client.post('forms/submit', body: {'answers': answers});
    return '${json['message'] ?? 'Submitted.'}';
  }
}
