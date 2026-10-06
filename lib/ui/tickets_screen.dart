import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../data/ticket_models.dart';
import '../state/ticket_state.dart';
import 'ticket_create_screen.dart';
import 'ticket_detail_screen.dart';
import 'widgets/common.dart';

/// Tickets tab: raise a ticket and follow its status.
class TicketsScreen extends StatefulWidget {
  const TicketsScreen({
    super.key,
    required this.state,
    this.department,
    this.isItStaff = false,
  });

  final TicketState state;

  /// IT staff see tickets assigned to them as well as their own, and get the
  /// work controls on each ticket.
  final bool isItStaff;

  /// The requester's own department, shown read-only on the create form.
  final String? department;

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  static const _filters = {
    'active': 'Active',
    'all': 'All',
    'open': 'Open',
    'in_progress': 'In progress',
    'resolved': 'Resolved',
    'closed': 'Closed',
  };

  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    widget.state.load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Wait for a pause in typing so we do not fire a request per keystroke.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 450),
      () => widget.state.setSearch(value.trim()),
    );
  }

  Future<void> _create() async {
    final ok = await showTicketCreateScreen(
      context,
      state: widget.state,
      department: widget.department,
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ticket raised. IT has been notified.'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  Future<void> _open(Ticket ticket) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TicketDetailScreen(
          api: widget.state.api,
          ticketId: ticket.id,
          initial: ticket,
        ),
      ),
    );
    // The detail screen can reply, acknowledge or re-raise — always re-sync.
    if (mounted) widget.state.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        // HomeShell keeps every tab alive in an IndexedStack, so the FABs
        // coexist and cannot share Flutter's default hero tag.
        heroTag: 'tickets-create-fab',
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New ticket'),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.state,
          builder: (context, _) {
            final s = widget.state;

            return RefreshIndicator(
              onRefresh: s.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.gutter,
                  8,
                  AppTheme.gutter,
                  96,
                ),
                children: [
                  Row(
                    children: [
                      Text(
                        'Tickets',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      if (widget.isItStaff) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            'IT',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.isItStaff
                        ? 'Tickets assigned to you, and the ones you raised'
                        : 'Raise an issue and track it to closure',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),

                  if (s.error != null) ...[
                    ErrorBanner(message: s.error!),
                    const SizedBox(height: 14),
                  ],

                  // The server picks the queue that matters to this role:
                  // unassigned work for the Super Admin, "on your desk" for
                  // IT, and work awaiting sign-off for everyone else.
                  if (s.dashboard.queue.isNotEmpty) ...[
                    _QueueCard(
                      dashboard: s.dashboard,
                      onOpen: _open,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Visible only to IT staff: everyone else has one scope.
                  if (widget.isItStaff) ...[
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'me',
                          label: Text('Assigned to me'),
                          icon: Icon(Icons.assignment_ind_outlined, size: 17),
                        ),
                        ButtonSegment(
                          value: 'raised',
                          label: Text('Raised by me'),
                          icon: Icon(Icons.edit_note_rounded, size: 17),
                        ),
                      ],
                      selected: {s.scope},
                      emptySelectionAllowed: true,
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      onSelectionChanged: (sel) =>
                          s.setScope(sel.isEmpty ? '' : sel.first),
                    ),
                    const SizedBox(height: 12),
                  ],

                  TextField(
                    controller: _search,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search tickets',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _search.clear();
                                widget.state.setSearch('');
                                setState(() {});
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final e in _filters.entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                s.counts[e.key] == null
                                    ? e.value
                                    : '${e.value} (${s.counts[e.key]})',
                              ),
                              selected: s.filter == e.key,
                              onSelected: (_) => s.setFilter(e.key),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  if (s.loading && s.tickets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (s.tickets.isEmpty)
                    SectionCard(
                      child: EmptyState(
                        icon: Icons.confirmation_number_outlined,
                        message: s.scope == 'me'
                            ? 'Nothing is assigned to you right now.'
                            : 'No tickets here.\nTap New ticket to raise one.',
                      ),
                    )
                  else
                    for (final t in s.tickets)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TicketCard(
                          ticket: t,
                          onTap: () => _open(t),
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

/// The caller's own queue, titled by the server.
class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.dashboard, required this.onOpen});

  final TicketDashboard dashboard;
  final ValueChanged<Ticket> onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final queue = dashboard.queue;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inbox_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dashboard.queueTitle.isEmpty
                      ? 'Your queue'
                      : dashboard.queueTitle,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '${queue.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ),
          if (dashboard.highOpen > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${dashboard.highOpen} high or urgent still open',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.danger,
                ),
              ),
            ),
          const SizedBox(height: 6),
          for (final t in queue.take(4))
            InkWell(
              onTap: () => onOpen(t),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: ticketStatusColor(t.status),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${t.reference} · ${t.priorityLabel}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 19,
                      color: scheme.outline,
                    ),
                  ],
                ),
              ),
            ),
          if (queue.length > 4)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'and ${queue.length - 4} more below',
                style:
                    TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class TicketCard extends StatelessWidget {
  const TicketCard({super.key, required this.ticket, this.onTap});

  final Ticket ticket;
  final VoidCallback? onTap;

  static final _when = DateFormat('d MMM, hh:mm a');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ticket.reference,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                StatusPill(
                  text: ticket.statusLabel,
                  color: ticketStatusColor(ticket.status),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              ticket.subject,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                if (ticket.location.isNotEmpty)
                  _Meta(icon: Icons.place_outlined, text: ticket.location),
                _Meta(
                  icon: Icons.flag_outlined,
                  text: ticket.priorityLabel,
                ),
                if (ticket.assignedTo != null && ticket.assignedTo!.isNotEmpty)
                  _Meta(
                    icon: Icons.engineering_outlined,
                    text: ticket.assignedTo!,
                  ),
                if (ticket.replyCount > 0)
                  _Meta(
                    icon: Icons.forum_outlined,
                    text: '${ticket.replyCount}',
                  ),
                if (ticket.createdAt != null)
                  _Meta(
                    icon: Icons.schedule_rounded,
                    text: _when.format(ticket.createdAt!),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

Color ticketStatusColor(TicketStatus status) {
  switch (status) {
    case TicketStatus.open:
    case TicketStatus.reopened:
      return AppTheme.danger;
    case TicketStatus.assigned:
    case TicketStatus.inProgress:
      return AppTheme.warning;
    case TicketStatus.resolved:
      return AppTheme.seed;
    case TicketStatus.closed:
      return AppTheme.success;
    case TicketStatus.unknown:
      return const Color(0xFF8A8F98);
  }
}
