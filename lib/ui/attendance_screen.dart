import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../data/attendance_models.dart';
import '../state/attendance_state.dart';
import 'widgets/common.dart';

/// "View attendance": the selected month day by day, with a month/year picker
/// so an employee can look back over past months.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, required this.state});

  final AttendanceState state;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  static final _monthYear = DateFormat('MMMM yyyy');
  static final _dayNum = DateFormat('d');
  static final _weekday = DateFormat('EEE');
  static final _time = DateFormat('hh:mm a');

  @override
  void initState() {
    super.initState();
    widget.state.load();
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => _MonthYearPicker(
        initial: widget.state.month,
        // Five years back covers any record an employee might look for, and
        // there is nothing to show beyond the current month.
        firstYear: now.year - 5,
        lastYear: now.year,
      ),
    );
    if (picked != null) await widget.state.setMonth(picked);
  }

  static bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.state,
          builder: (context, _) {
            final s = widget.state;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.gutter,
                    8,
                    AppTheme.gutter,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Attendance',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 14),
                      _MonthBar(
                        label: _monthYear.format(s.month),
                        subtitle: s.isCurrentMonth ? 'This month' : null,
                        onPrevious: () => s.step(-1),
                        onNext: s.canGoForward ? () => s.step(1) : null,
                        onTap: _pickMonth,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: s.load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.gutter,
                        14,
                        AppTheme.gutter,
                        32,
                      ),
                      children: [
                        if (s.error != null) ...[
                          ErrorBanner(message: s.error!),
                          const SizedBox(height: 14),
                        ],
                        _StatsCard(stats: s.stats),
                        const SizedBox(height: 18),
                        if (s.loading && s.days.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 44),
                            child:
                                Center(child: CircularProgressIndicator()),
                          )
                        else if (s.days.isEmpty)
                          const SectionCard(
                            child: EmptyState(
                              icon: Icons.event_note_outlined,
                              message: 'No attendance recorded for this month.',
                            ),
                          )
                        else ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10, left: 4),
                            child: Text(
                              '${s.days.length} '
                              '${s.days.length == 1 ? 'day' : 'days'}',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          for (final day in s.days)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _DayRow(
                                day: day,
                                isToday: _isToday(day.date),
                                dayNum: _dayNum.format(day.date),
                                weekday: _weekday.format(day.date),
                                inTime: day.punchIn == null
                                    ? '—'
                                    : _time.format(day.punchIn!),
                                outTime: day.punchOut == null
                                    ? '—'
                                    : _time.format(day.punchOut!),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Month stepper plus a tap target that opens the month/year picker.
class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.label,
    required this.subtitle,
    required this.onPrevious,
    required this.onNext,
    required this.onTap,
  });

  final String label;
  final String? subtitle;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Previous month',
          ),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_drop_down_rounded,
                          size: 22,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Next month',
          ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final MonthStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Only show the categories that actually occurred, so a normal month is
    // not padded with a row of zeros.
    final chips = <({String label, int value, Color colour})>[
      (label: 'Present', value: stats.present, colour: AppTheme.success),
      (label: 'Absent', value: stats.absent, colour: AppTheme.danger),
      (label: 'Leave', value: stats.leave, colour: AppTheme.warning),
      (label: 'Half day', value: stats.halfDay, colour: AppTheme.warning),
      (label: 'On duty', value: stats.onDuty, colour: AppTheme.success),
      (label: 'Comp off', value: stats.compOff, colour: AppTheme.success),
      (label: 'Holiday', value: stats.holiday, colour: scheme.primary),
      (label: 'Week off', value: stats.weekOff, colour: scheme.outline),
      (label: 'No punch out', value: stats.incomplete, colour: AppTheme.warning),
    ].where((c) => c.value > 0).toList();

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total hours',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Text(
                formatWorked(stats.totalWorked),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (stats.payableDays > 0)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '${stats.payableDays} payable '
                '${stats.payableDays == 1 ? 'day' : 'days'}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: c.colour.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      '${c.label} ${c.value}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: c.colour,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.isToday,
    required this.dayNum,
    required this.weekday,
    required this.inTime,
    required this.outTime,
  });

  final AttendanceDay day;
  final bool isToday;
  final String dayNum;
  final String weekday;
  final String inTime;
  final String outTime;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Today has not finished, so the server marking it Absent only means
    // "no punches yet". Showing that in red alongside the real absences of the
    // month would misread the day.
    final pending = isToday && day.punchCount == 0;
    final colour =
        pending ? scheme.outline : dayMarkColour(day.mark, scheme);
    final label = pending ? 'Not marked yet' : dayMarkLabel(day.mark);

    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          // Date block.
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: colour.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  dayNum,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: colour,
                  ),
                ),
                Text(
                  weekday,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: colour,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Punch(
                      icon: Icons.login_rounded,
                      value: inTime,
                      colour: AppTheme.success,
                    ),
                    const SizedBox(width: 14),
                    _Punch(
                      icon: Icons.logout_rounded,
                      value: outTime,
                      colour: AppTheme.danger,
                    ),
                  ],
                ),
                if (day.isOpen)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      day.punchCount > 1
                          ? '${day.punchCount} punches, one left open'
                          : 'No punch out recorded',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.warning,
                      ),
                    ),
                  )
                else if (day.punchCount > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      '${day.punchCount} punches',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else if (day.location != null && day.location!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      day.location!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatWorked(day.worked),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: colour,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Punch extends StatelessWidget {
  const _Punch({
    required this.icon,
    required this.value,
    required this.colour,
  });

  final IconData icon;
  final String value;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colour),
        const SizedBox(width: 5),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

Color dayMarkColour(DayMark mark, ColorScheme scheme) {
  switch (mark) {
    case DayMark.present:
    case DayMark.onDuty:
    case DayMark.compOff:
      return AppTheme.success;
    case DayMark.absent:
      return AppTheme.danger;
    case DayMark.leave:
    case DayMark.halfDay:
      return AppTheme.warning;
    case DayMark.holiday:
      return scheme.primary;
    case DayMark.weekOff:
    case DayMark.unknown:
      return scheme.outline;
  }
}

/// Year row plus a month grid — quicker than stepping back month by month
/// when an employee wants last September.
class _MonthYearPicker extends StatefulWidget {
  const _MonthYearPicker({
    required this.initial,
    required this.firstYear,
    required this.lastYear,
  });

  final DateTime initial;
  final int firstYear;
  final int lastYear;

  @override
  State<_MonthYearPicker> createState() => _MonthYearPickerState();
}

class _MonthYearPickerState extends State<_MonthYearPicker> {
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  late int _year = widget.initial.year;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();

    return AlertDialog(
      title: const Text('Select month'),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: _year > widget.firstYear
                      ? () => setState(() => _year--)
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Text(
                  '$_year',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  onPressed: _year < widget.lastYear
                      ? () => setState(() => _year++)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.9,
              children: [
                for (var m = 1; m <= 12; m++)
                  _MonthCell(
                    label: _months[m - 1],
                    selected: _year == widget.initial.year &&
                        m == widget.initial.month,
                    // A month that has not happened yet holds no attendance.
                    enabled: DateTime(_year, m)
                        .isBefore(DateTime(now.year, now.month + 1)),
                    scheme: scheme,
                    onTap: () => Navigator.pop(context, DateTime(_year, m)),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.scheme,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;

    if (selected) {
      background = scheme.primary;
      foreground = scheme.onPrimary;
    } else if (enabled) {
      background = scheme.surfaceContainerHighest.withValues(alpha: 0.6);
      foreground = scheme.onSurface;
    } else {
      background = Colors.transparent;
      foreground = scheme.outline;
    }

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}
