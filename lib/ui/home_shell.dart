import 'package:flutter/material.dart';

import '../core/device_services.dart';
import '../state/app_state.dart';
import '../state/attendance_state.dart';
import '../state/leave_state.dart';
import '../state/task_form_state.dart';
import '../state/ticket_state.dart';
import 'attendance_screen.dart';
import 'dashboard_screen.dart';
import 'leave_screen.dart';
import 'profile_screen.dart';
import 'tickets_screen.dart';

/// Bottom-nav container for the signed-in experience.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.state,
    required this.attendance,
    required this.leave,
    required this.tickets,
    required this.forms,
    required this.services,
    required this.themeMode,
    required this.onThemeChanged,
  });

  final AppState state;
  final AttendanceState attendance;
  final LeaveState leave;
  final TicketState tickets;
  final TaskFormState forms;
  final DeviceServices services;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // The shell is rebuilt on every sign-in, so this always reflects the
    // current employee's department. Drop the previous user's form first.
    widget.forms.clear();
    widget.forms.load();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(
        state: widget.state,
        services: widget.services,
        forms: widget.forms,
      ),
      AttendanceScreen(state: widget.attendance),
      LeaveScreen(state: widget.leave),
      TicketsScreen(
        state: widget.tickets,
        department: widget.state.employee?.department,
        isItStaff: widget.state.employee?.isItStaff ?? false,
      ),
      ProfileScreen(
        state: widget.state,
        themeMode: widget.themeMode,
        onThemeChanged: widget.onThemeChanged,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Attendance',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note_rounded),
            label: 'Leave',
          ),
          NavigationDestination(
            icon: Icon(Icons.confirmation_number_outlined),
            selectedIcon: Icon(Icons.confirmation_number_rounded),
            label: 'Tickets',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
