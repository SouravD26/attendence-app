import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/device_services.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../state/task_form_state.dart';
import 'punch_screen.dart';
import 'task_form_screen.dart';
import 'widgets/common.dart';
import 'widgets/punch_dial.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.state,
    required this.services,
    required this.forms,
  });

  final AppState state;
  final DeviceServices services;

  /// Department daily-task form; the entry card shows only when one exists.
  final TaskFormState forms;

  static final _time = DateFormat('hh:mm a');
  static final _date = DateFormat('EEEE, d MMMM');

  String _elapsed(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Future<void> _punch(BuildContext context) async {
    final checkingIn = !(state.today?.isCheckedIn ?? false);

    final punchContext = await showPunchScreen(
      context,
      checkingIn: checkingIn,
      services: services,
    );
    if (punchContext == null || !context.mounted) return;

    final result = await state.punch(punchContext);
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    if (result == PunchType.none) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(state.error ?? 'Punch failed.'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result == PunchType.checkIn
                ? 'Checked in at ${_time.format(DateTime.now())}'
                : 'Checked out at ${_time.format(DateTime.now())}',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = state.today;
    final employee = state.employee;

    final checkedIn = today?.isCheckedIn ?? false;
    final complete = today?.isComplete ?? false;
    // Only meaningful once a first session has closed and the day is not
    // locked - lets the caption say "Total hours today" instead of prompting
    // to start over.
    final hasPriorSession = !checkedIn &&
        !complete &&
        (today?.checkOut != null ||
            (today?.priorWorked ?? Duration.zero) > Duration.zero);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => Future.wait([state.refresh(), forms.load()]),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppTheme.gutter,
              8,
              AppTheme.gutter,
              32,
            ),
            children: [
              // Greeting header.
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting(now),
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          employee?.name ?? '-',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: scheme.primary.withValues(alpha: 0.14),
                    child: Text(
                      _initials(employee?.name),
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // Punch card - the centre of the app.
              SectionCard(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _date.format(now),
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        StatusPill(
                          text: complete
                              ? 'Day complete'
                              : checkedIn
                                  ? 'Checked in'
                                  : 'Not checked in',
                          color: complete
                              ? scheme.primary
                              : checkedIn
                                  ? AppTheme.success
                                  : AppTheme.warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    PunchDial(
                      progress: today?.progressAt(now) ?? 0,
                      active: checkedIn,
                      label: _elapsed(today?.workedAt(now) ?? Duration.zero),
                      caption: checkedIn
                          ? 'since ${_time.format(today!.checkIn!)}'
                          : complete
                              ? 'Total hours today'
                              : hasPriorSession
                                  ? 'Total hours today'
                                  : 'Tap below to start your day',
                    ),
                    const SizedBox(height: 26),
                    FilledButton.icon(
                      onPressed:
                          state.busy || complete ? null : () => _punch(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: complete
                            ? scheme.surfaceContainerHighest
                            : checkedIn
                                ? AppTheme.danger
                                : AppTheme.success,
                      ),
                      icon: state.busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              complete
                                  ? Icons.check_circle_outline_rounded
                                  : checkedIn
                                      ? Icons.logout_rounded
                                      : Icons.login_rounded,
                            ),
                      label: Text(
                        complete
                            ? 'Attendance recorded'
                            : checkedIn
                                ? 'Check out'
                                : 'Check in',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Today's numbers.
              SectionCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: StatTile(
                        icon: Icons.login_rounded,
                        label: 'Check in',
                        value: today?.checkIn == null
                            ? '--:--'
                            : _time.format(today!.checkIn!),
                        tint: AppTheme.success,
                      ),
                    ),
                    Expanded(
                      child: StatTile(
                        icon: Icons.logout_rounded,
                        label: 'Check out',
                        value: today?.checkOut == null
                            ? '--:--'
                            : _time.format(today!.checkOut!),
                        tint: AppTheme.danger,
                      ),
                    ),
                    Expanded(
                      child: StatTile(
                        icon: Icons.timelapse_rounded,
                        label: 'Worked',
                        value: _short(today?.workedAt(now) ?? Duration.zero),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedBuilder(
                animation: forms,
                builder: (context, _) {
                  final form = forms.form;
                  if (!forms.hasForm || form == null) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.gutter,
                          vertical: 8,
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.assignment_rounded,
                            size: 20,
                            color: scheme.primary,
                          ),
                        ),
                        title: const Text(
                          'Daily Task Form',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(form.label),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => showTaskFormScreen(context, state: forms),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.length == 1
        ? parts.first.substring(0, 1).toUpperCase()
        : (parts.first[0] + parts.last[0]).toUpperCase();
  }

  static String _short(Duration d) =>
      '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
}
