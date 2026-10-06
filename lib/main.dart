import 'package:flutter/material.dart';

import 'core/device_services.dart';
import 'core/theme.dart';
import 'data/attendance_api.dart';
import 'data/hrms_repository.dart';
import 'data/leave_api.dart';
import 'data/task_form_api.dart';
import 'data/ticket_api.dart';
import 'state/app_state.dart';
import 'state/attendance_state.dart';
import 'state/leave_state.dart';
import 'state/task_form_state.dart';
import 'state/ticket_state.dart';
import 'ui/home_shell.dart';
import 'ui/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Live HRMS backend. Swap for MockAttendanceRepository() to run the UI
  // without a server (that is what the widget tests use).
  final repository = HrmsRepository();

  // Leave and tickets share the repository's ApiClient, so all three features
  // use the same bearer token and the same 401 handling.
  runApp(AttendanceApp(
    state: AppState(repository),
    attendance: AttendanceState(AttendanceApi(repository.client)),
    leave: LeaveState(LeaveApi(repository.client)),
    tickets: TicketState(TicketApi(repository.client)),
    forms: TaskFormState(TaskFormApi(repository.client)),
  ));
}

class AttendanceApp extends StatefulWidget {
  const AttendanceApp({
    super.key,
    required this.state,
    required this.attendance,
    required this.leave,
    required this.tickets,
    required this.forms,
  });

  final AppState state;
  final AttendanceState attendance;
  final LeaveState leave;
  final TicketState tickets;
  final TaskFormState forms;

  @override
  State<AttendanceApp> createState() => _AttendanceAppState();
}

class _AttendanceAppState extends State<AttendanceApp> {
  final _services = DeviceServices();
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    widget.state.restoreSession();
  }

  @override
  void dispose() {
    widget.state.dispose();
    widget.attendance.dispose();
    widget.leave.dispose();
    widget.tickets.dispose();
    widget.forms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sanmarg Attendance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      home: AnimatedBuilder(
        animation: widget.state,
        builder: (context, _) {
          final Widget screen;
          switch (widget.state.auth) {
            case AuthStatus.restoring:
              screen = const _SplashScreen(key: ValueKey('splash'));
            case AuthStatus.signedIn:
              screen = HomeShell(
                key: const ValueKey('home'),
                state: widget.state,
                attendance: widget.attendance,
                leave: widget.leave,
                tickets: widget.tickets,
                forms: widget.forms,
                services: _services,
                themeMode: _themeMode,
                onThemeChanged: (mode) => setState(() => _themeMode = mode),
              );
            case AuthStatus.signedOut:
            case AuthStatus.signingIn:
              screen = LoginScreen(
                key: const ValueKey('login'),
                state: widget.state,
              );
          }

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            child: screen,
          );
        },
      ),
    );
  }
}

/// Shown for the moment it takes to validate a stored token.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                gradient: brandGradient(context),
                borderRadius: BorderRadius.circular(20),
              ),
              // child: const Icon(
              //   Icons.fingerprint_rounded,
              //   color: Colors.white,
              //   size: 34,
              // ),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ],
        ),
      ),
    );
  }
}
