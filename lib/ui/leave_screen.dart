import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../data/leave_models.dart';
import '../state/leave_state.dart';
import 'leave_apply_screen.dart';
import 'widgets/common.dart';

/// Leave tab: balance at the top, then the employee's own applications.
class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key, required this.state});

  final LeaveState state;

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  static final _short = DateFormat('d MMM');
  static final _long = DateFormat('d MMM yyyy');

  static const _filters = {
    'all': 'All',
    'pending': 'Pending',
    'approved': 'Approved',
    'rejected': 'Rejected',
  };

  @override
  void initState() {
    super.initState();
    widget.state.load();
  }

  Future<void> _apply() async {
    final ok = await showLeaveApplyScreen(context, state: widget.state);
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Leave request submitted for approval.'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  Future<void> _cancel(LeaveApplication leave) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: Text('${leave.typeName} on ${_span(leave)} will be withdrawn.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.danger,
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final error = await widget.state.cancel(leave.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Request cancelled.'),
        backgroundColor: error == null ? AppTheme.success : AppTheme.danger,
      ),
    );
  }

  String _span(LeaveApplication l) {
    if (l.from == null) return 'Dates not set';
    if (l.to == null || _sameDay(l.from!, l.to!)) return _long.format(l.from!);
    return '${_short.format(l.from!)} - ${_long.format(l.to!)}';
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        // HomeShell keeps every tab alive in an IndexedStack, so the FABs
        // coexist and cannot share Flutter's default hero tag.
        heroTag: 'leave-apply-fab',
        onPressed: _apply,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Apply'),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.state,
          builder: (context, _) {
            final s = widget.state;

            return RefreshIndicator(
              onRefresh: s.load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.gutter,
                  8,
                  AppTheme.gutter,
                  96,
                ),
                children: [
                  Text(
                    'Leave',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your balance and requests',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 18),
                  if (s.error != null) ...[
                    ErrorBanner(message: s.error!),
                    const SizedBox(height: 14),
                  ],
                  _SummaryCard(state: s),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final e in _filters.entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(e.value),
                              selected: s.filter == e.key,
                              onSelected: (_) => s.setFilter(e.key),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (s.loading && s.applications.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (s.applications.isEmpty)
                    const SectionCard(
                      child: EmptyState(
                        icon: Icons.event_busy_rounded,
                        message: 'No leave requests here yet.\n'
                            'Tap Apply to raise one.',
                      ),
                    )
                  else
                    for (final leave in s.applications)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _LeaveCard(
                          leave: leave,
                          span: _span(leave),
                          onCancel:
                              leave.isCancellable ? () => _cancel(leave) : null,
                        ),
                      ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Headline figures: what has been approved, and how much leave is used.
/// The per-type allowance breakdown is deliberately not shown - every type
/// currently reports a zero allowance, so it carried no information.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state});

  final LeaveState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final approved = state.approvedDays;
    final taken = state.takenDays;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Figure(
                  value: formatDays(approved),
                  unit: approved == 1 ? 'day' : 'days',
                  label: 'Approved',
                  colour: AppTheme.success,
                ),
              ),
              Container(
                width: 1,
                height: 42,
                color: scheme.outlineVariant,
              ),
              Expanded(
                child: _Figure(
                  value: formatDays(taken),
                  unit: taken == 1 ? 'day' : 'days',
                  label: 'Total taken',
                  colour: scheme.primary,
                ),
              ),
            ],
          ),
          if (state.pendingCount > 0) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${state.pendingCount} '
                '${state.pendingCount == 1 ? 'request' : 'requests'} '
                'awaiting approval '
                '(${formatDays(state.pendingDays)} '
                '${state.pendingDays == 1 ? 'day' : 'days'})',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.warning,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.unit,
    required this.label,
    required this.colour,
  });

  final String value;
  final String unit;
  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: colour,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              unit,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _LeaveCard extends StatelessWidget {
  const _LeaveCard({required this.leave, required this.span, this.onCancel});

  final LeaveApplication leave;
  final String span;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unit = leave.days == 1 ? 'day' : 'days';

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  leave.typeName,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              StatusPill(
                text: leave.statusLabel,
                color: leaveStatusColor(leave.status),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.date_range_rounded,
                size: 15,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$span  ·  ${formatDays(leave.days)} $unit',
                  style:
                      TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          if (leave.reason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(leave.reason, style: const TextStyle(fontSize: 13.5)),
          ],
          if (leave.remarks != null && leave.remarks!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                leave.remarks!,
                style:
                    TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
          if (onCancel != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded, size: 17),
                label: const Text('Cancel request'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Color leaveStatusColor(LeaveStatus status) {
  switch (status) {
    case LeaveStatus.approved:
      return AppTheme.success;
    case LeaveStatus.rejected:
      return AppTheme.danger;
    case LeaveStatus.cancelled:
      return const Color(0xFF8A8F98);
    case LeaveStatus.pending:
    case LeaveStatus.unknown:
      return AppTheme.warning;
  }
}

/// Days come back as 1, 1.5, 2 — show halves but never a trailing zero.
String formatDays(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
