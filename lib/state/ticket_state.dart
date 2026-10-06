import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../data/ticket_api.dart';
import '../data/ticket_models.dart';

/// Tickets tab state: the list with its filter/search, plus the form options.
class TicketState extends ChangeNotifier {
  TicketState(this.api);

  final TicketApi api;

  List<Ticket> _tickets = const [];
  Map<String, int> _counts = const {};
  TicketFormOptions _options = const TicketFormOptions();
  TicketDashboard _dashboard = TicketDashboard.empty;
  String _filter = 'active';
  String _search = '';

  /// Which tickets to show: everything in scope, only those assigned to me, or
  /// only the ones I raised. IT staff get the choice; everyone else sees their
  /// own either way.
  String _scope = '';
  bool _loading = false;
  bool _submitting = false;
  String? _error;

  List<Ticket> get tickets => _tickets;
  Map<String, int> get counts => _counts;
  TicketFormOptions get options => _options;
  TicketDashboard get dashboard => _dashboard;
  String get filter => _filter;
  String get search => _search;
  String get scope => _scope;
  bool get loading => _loading;
  bool get submitting => _submitting;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    await Future.wait([_fetch(), _loadDashboard()]);
    // Form options rarely change — fetch once and keep them.
    if (_options.locations.isEmpty) {
      try {
        _options = await api.formOptions();
      } catch (_) {
        // The create sheet falls back to a free-text location field.
      }
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _loadDashboard() async {
    try {
      _dashboard = await api.dashboard();
    } catch (_) {
      // The list still works without it; the queue card simply hides.
    }
  }

  Future<void> _fetch() async {
    try {
      final result =
          await api.list(status: _filter, search: _search, assigned: _scope);
      _tickets = result.tickets;
      if (result.counts.isNotEmpty) _counts = result.counts;
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not load your tickets.';
    }
  }

  Future<void> refresh() async {
    await Future.wait([_fetch(), _loadDashboard()]);
    notifyListeners();
  }

  Future<void> setFilter(String value) async {
    if (_filter == value) return;
    _filter = value;
    notifyListeners();
    await refresh();
  }

  Future<void> setScope(String value) async {
    if (_scope == value) return;
    _scope = value;
    notifyListeners();
    await refresh();
  }

  Future<void> setSearch(String value) async {
    if (_search == value) return;
    _search = value;
    await refresh();
  }

  /// Returns null on success, or the message to show the user.
  Future<String?> create({
    required String subject,
    required String body,
    required String location,
    required bool trainedBefore,
    List<String> photos = const [],
  }) async {
    if (_submitting) return null;
    _submitting = true;
    notifyListeners();
    try {
      await api.create(
        subject: subject,
        body: body,
        location: location,
        trainedBefore: trainedBefore,
        photos: photos,
      );
      await refresh();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not raise the ticket. Please try again.';
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }
}
