import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attendence/data/api_client.dart';
import 'package:attendence/data/attendance_api.dart';
import 'package:attendence/data/attendance_repository.dart';
import 'package:attendence/data/leave_api.dart';
import 'package:attendence/data/task_form_api.dart';
import 'package:attendence/data/ticket_api.dart';
import 'package:attendence/main.dart';
import 'package:attendence/state/app_state.dart';
import 'package:attendence/state/attendance_state.dart';
import 'package:attendence/state/leave_state.dart';
import 'package:attendence/state/task_form_state.dart';
import 'package:attendence/state/ticket_state.dart';

/// Boots the app against the mock backend and pumps past the splash screen,
/// which is shown while a stored session token is validated.
Future<void> bootApp(WidgetTester tester) async {
  await tester.pumpWidget(
    AttendanceApp(
      state: AppState(MockAttendanceRepository()),
      // These tabs are never reached while signed out, so an unused client is
      // enough to satisfy the constructor.
      attendance: AttendanceState(AttendanceApi(ApiClient())),
      leave: LeaveState(LeaveApi(ApiClient())),
      tickets: TicketState(TicketApi(ApiClient())),
      forms: TaskFormState(TaskFormApi(ApiClient())),
    ),
  );
  await tester.pump(); // restoreSession resolves (no stored token)
  await tester.pump(const Duration(milliseconds: 400)); // splash -> login
}

void main() {
  testWidgets('shows the login screen when signed out', (tester) async {
    await bootApp(tester);

    expect(find.text('Sign in to Sanmarg'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('rejects an empty form', (tester) async {
    await bootApp(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Employee ID is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
  });

  testWidgets('signs in and lands on the dashboard', (tester) async {
    await bootApp(tester);

    await tester.enterText(find.byType(TextFormField).first, '9800000000');
    await tester.enterText(find.byType(TextFormField).last, 'secret');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Check in'), findsWidgets);
  });
}
