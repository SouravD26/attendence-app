import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../data/ticket_api.dart';
import '../data/ticket_models.dart';
import 'tickets_screen.dart';
import 'widgets/common.dart';

/// One ticket: the request, the conversation, and the actions the API says
/// this user is allowed to take (`can_reply` / `can_acknowledge` /
/// `can_reraise`) — the server owns those rules, the app just draws them.
class TicketDetailScreen extends StatefulWidget {
  const TicketDetailScreen({
    super.key,
    required this.api,
    required this.ticketId,
    this.initial,
  });

  final TicketApi api;
  final String ticketId;

  /// The list row we came from, shown while the full detail loads.
  final Ticket? initial;

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  static final _when = DateFormat('d MMM yyyy, hh:mm a');

  final _reply = TextEditingController();

  TicketDetail? _detail;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// Assignable people, fetched only when this user may actually assign.
  List<ItStaff> _staff = const [];

  /// IT staff can mark a reply as an internal note, hidden from the requester.
  bool _internal = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final detail = await widget.api.show(widget.ticketId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _error = null;
        _loading = false;
      });
      if (detail.ticket.canAssign && _staff.isEmpty) _loadStaff();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this ticket.';
        _loading = false;
      });
    }
  }

  Future<void> _loadStaff() async {
    try {
      final staff = await widget.api.itStaff();
      if (mounted) setState(() => _staff = staff);
    } catch (_) {
      // The assignee picker simply stays empty; nothing else depends on it.
    }
  }

  /// Runs an action, then reloads so the status and buttons come from the
  /// server rather than from a guess about what the action did.
  Future<void> _act(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    String? error;
    try {
      await action();
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'That did not go through. Please try again.';
    }
    if (!mounted) return;
    setState(() => _busy = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? success),
        backgroundColor: error == null ? AppTheme.success : AppTheme.danger,
      ),
    );
    if (error == null) await _load();
  }

  Future<void> _sendReply() async {
    final message = _reply.text.trim();
    if (message.isEmpty) return;
    await _act(
      () => widget.api.reply(widget.ticketId, message, internal: _internal),
      _internal ? 'Internal note added.' : 'Reply sent.',
    );
    if (mounted) _reply.clear();
  }

  Future<void> _acknowledge() async {
    final ok = await _confirm(
      title: 'Close this ticket?',
      body: 'Confirming that the issue is fixed will close the ticket.',
      action: 'Yes, it is fixed',
      colour: AppTheme.success,
    );
    if (ok != true) return;
    await _act(
      () => widget.api.acknowledge(widget.ticketId),
      'Thanks — the ticket is closed.',
    );
  }

  Future<void> _reraise() async {
    final reason = await _askReason();
    if (reason == null) return;
    await _act(
      () => widget.api.reraise(widget.ticketId, reason: reason),
      'Sent back to IT.',
    );
  }

  Future<void> _setStatus(String status) => _act(
        () => widget.api.update(widget.ticketId, status: status),
        'Status updated.',
      );

  /// Completing a ticket hands it back to the person who raised it, so the
  /// work done is written down first - they see that note when deciding
  /// whether to acknowledge.
  Future<void> _complete() async {
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Mark as completed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Describe what you did. The person who raised the ticket '
                'sees this and confirms the fix.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'What did you do to fix it?',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.success,
                minimumSize: const Size(0, 44),
              ),
              child: const Text('Complete'),
            ),
          ],
        );
      },
    );
    if (note == null) return;

    if (note.isEmpty) {
      return _toastError('Write what you did before completing the ticket.');
    }

    await _act(
      () async {
        // The note goes first: if the status change fails, the work is still
        // recorded rather than lost.
        await widget.api.reply(widget.ticketId, note);
        await widget.api.update(widget.ticketId, status: 'resolved');
      },
      'Completed. Sent back to the requester to confirm.',
    );
  }

  /// Priority rides along with tickets/assign, the endpoint built for it.
  Future<void> _setPriority(String priority) => _act(
        () => widget.api.assign(
          widget.ticketId,
          assignedTo: _detail?.ticket.assignedToId,
          priority: priority,
        ),
        'Priority updated.',
      );

  Future<void> _assign() async {
    if (_staff.isEmpty) {
      await _loadStaff();
      if (!mounted || _staff.isEmpty) {
        return _toastError('No assignable IT staff were returned.');
      }
    }

    final chosen = await showModalBottomSheet<ItStaff>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text(
                'Assign to',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            for (final person in _staff)
              ListTile(
                leading: CircleAvatar(
                  radius: 17,
                  child: Text(
                    person.name.isEmpty ? '?' : person.name[0].toUpperCase(),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                title: Text(person.name),
                subtitle: Text(
                  [
                    if (person.designation != null &&
                        person.designation!.isNotEmpty)
                      person.designation!,
                    if (person.department != null &&
                        person.department!.isNotEmpty)
                      person.department!,
                  ].join(' · '),
                ),
                onTap: () => Navigator.pop(sheet, person),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;

    await _act(
      () => widget.api.assign(widget.ticketId, assignedTo: chosen.id),
      'Assigned to ${chosen.name}.',
    );
  }

  void _toastError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
    );
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
    required Color colour,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not yet'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: colour,
                minimumSize: const Size(0, 44),
              ),
              child: Text(action),
            ),
          ],
        ),
      );

  Future<String?> _askReason() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Still not working?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'What is still wrong? (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Re-raise'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _detail?.ticket ?? widget.initial;

    return Scaffold(
      appBar: AppBar(
        title: Text(ticket?.reference ?? 'Ticket'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      bottomNavigationBar: ticket != null && ticket.canReply
          ? _ReplyBar(
              controller: _reply,
              busy: _busy,
              onSend: _sendReply,
              // Only the people working the ticket can post internal notes.
              canBeInternal: ticket.canUpdate,
              internal: _internal,
              onInternalChanged: (v) => setState(() => _internal = v),
            )
          : null,
      body: _loading && _detail == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.gutter,
                  8,
                  AppTheme.gutter,
                  32,
                ),
                children: [
                  if (_error != null) ...[
                    ErrorBanner(message: _error!),
                    const SizedBox(height: 14),
                  ],
                  if (ticket != null) ...[
                    _Header(ticket: ticket),
                    const SizedBox(height: 16),
                    if (ticket.canAcknowledge || ticket.canReraise) ...[
                      _Actions(
                        ticket: ticket,
                        busy: _busy,
                        onAcknowledge: _acknowledge,
                        onReraise: _reraise,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                  if (ticket != null && ticket.canUpdate) ...[
                    _ItActions(
                      ticket: ticket,
                      busy: _busy,
                      onStatus: _setStatus,
                      onComplete: _complete,
                      onPriority: _setPriority,
                      onAssign: _assign,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if ((_detail?.attachments ?? const []).isNotEmpty) ...[
                    _Photos(attachments: _detail!.attachments),
                    const SizedBox(height: 16),
                  ],
                  _Conversation(
                    replies: _detail?.replies ?? const [],
                    formatter: _when,
                  ),
                  const SizedBox(height: 16),
                  if ((_detail?.activity ?? const []).isNotEmpty)
                    _ActivityTrail(
                      activity: _detail!.activity,
                      formatter: _when,
                    ),
                ],
              ),
            ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.ticket});

  final Ticket ticket;

  static final _when = DateFormat('d MMM yyyy, hh:mm a');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ticket.subject,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              StatusPill(
                text: ticket.statusLabel,
                color: ticketStatusColor(ticket.status),
              ),
            ],
          ),
          if (ticket.body.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(ticket.body, style: const TextStyle(fontSize: 14, height: 1.45)),
          ],
          const SizedBox(height: 16),
          Divider(color: scheme.outlineVariant, height: 1),
          const SizedBox(height: 14),
          _Field(label: 'Priority', value: ticket.priorityLabel),
          if (ticket.location.isNotEmpty)
            _Field(label: 'Location', value: ticket.location),
          if (ticket.department != null && ticket.department!.isNotEmpty)
            _Field(label: 'Department', value: ticket.department!),
          _Field(
            label: 'Assigned to',
            value: (ticket.assignedTo == null || ticket.assignedTo!.isEmpty)
                ? 'Not assigned yet'
                : ticket.assignedTo!,
          ),
          if (ticket.createdAt != null)
            _Field(label: 'Raised on', value: _when.format(ticket.createdAt!)),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.ticket,
    required this.busy,
    required this.onAcknowledge,
    required this.onReraise,
  });

  final Ticket ticket;
  final bool busy;
  final VoidCallback onAcknowledge;
  final VoidCallback onReraise;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'IT has marked this resolved.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (ticket.canAcknowledge)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onAcknowledge,
                    icon: const Icon(Icons.check_rounded, size: 19),
                    label: const Text('It is fixed'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
              if (ticket.canAcknowledge && ticket.canReraise)
                const SizedBox(width: 12),
              if (ticket.canReraise)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onReraise,
                    icon: const Icon(Icons.replay_rounded, size: 19),
                    label: const Text('Still broken'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Photos attached to the ticket. The links are signed and expiring, so they
/// load in an Image without a bearer header.
class _Photos extends StatelessWidget {
  const _Photos({required this.attachments});

  final List<TicketAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final images = attachments.where((a) => a.isImage && a.url != null).toList();
    if (images.isEmpty) return const SizedBox.shrink();

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            images.length == 1 ? 'Photo' : '${images.length} photos',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final a = images[i];
                return GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _PhotoViewer(attachment: a),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      a.url!,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 96,
                        height: 96,
                        color: scheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: scheme.outline,
                        ),
                      ),
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                              ? child
                              : Container(
                                  width: 96,
                                  height: 96,
                                  color: scheme.surfaceContainerHighest,
                                  child: const Center(
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen view of one attachment, pinch to zoom.
class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.attachment});

  final TicketAttachment attachment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          attachment.name,
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.network(
            attachment.url!,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text(
              'Could not load this photo.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}

class _Conversation extends StatelessWidget {
  const _Conversation({required this.replies, required this.formatter});

  final List<TicketReply> replies;
  final DateFormat formatter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conversation',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          if (replies.isEmpty)
            const EmptyState(
              icon: Icons.forum_outlined,
              message: 'No replies yet. IT will respond here.',
            )
          else
            for (final r in replies) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: scheme.primary.withValues(alpha: 0.14),
                    child: Text(
                      _initials(r.author),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                r.author,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (r.isInternal) ...[
                              const SizedBox(width: 8),
                              StatusPill(
                                text: 'Internal',
                                color: AppTheme.warning,
                              ),
                            ],
                          ],
                        ),
                        if (r.at != null)
                          Text(
                            formatter.format(r.at!),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          r.message,
                          style: const TextStyle(fontSize: 13.5, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

class _ActivityTrail extends StatelessWidget {
  const _ActivityTrail({required this.activity, required this.formatter});

  final List<TicketActivity> activity;
  final DateFormat formatter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'History',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          for (final a in activity)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.text, style: const TextStyle(fontSize: 13.5)),
                        Text(
                          [
                            if (a.by != null && a.by!.isNotEmpty) a.by!,
                            if (a.at != null) formatter.format(a.at!),
                          ].join('  ·  '),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({
    required this.controller,
    required this.busy,
    required this.onSend,
    this.canBeInternal = false,
    this.internal = false,
    this.onInternalChanged,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  final bool canBeInternal;
  final bool internal;
  final ValueChanged<bool>? onInternalChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppTheme.gutter,
          right: AppTheme.gutter,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canBeInternal)
              Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: () => onInternalChanged?.call(!internal),
                  borderRadius: BorderRadius.circular(100),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          internal
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 19,
                          color: internal ? AppTheme.warning : scheme.outline,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          'Internal note (hidden from the requester)',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight:
                                internal ? FontWeight.w600 : FontWeight.w400,
                            color: internal
                                ? AppTheme.warning
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: internal ? 'Write an internal note' : 'Write a reply',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 52,
              height: 52,
              child: FilledButton(
                onPressed: busy ? null : onSend,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(52, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(Icons.send_rounded, size: 20, color: scheme.onPrimary),
              ),
            ),
          ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The IT workspace: what the people working a ticket can change.
///
/// Which controls appear is decided by the server through `can_update`,
/// `can_assign` and `settable_statuses`, so this never second-guesses the
/// permission rules.
class _ItActions extends StatelessWidget {
  const _ItActions({
    required this.ticket,
    required this.busy,
    required this.onStatus,
    required this.onComplete,
    required this.onPriority,
    required this.onAssign,
  });

  final Ticket ticket;
  final bool busy;
  final ValueChanged<String> onStatus;
  final VoidCallback onComplete;
  final ValueChanged<String> onPriority;
  final VoidCallback onAssign;

  static const _statusLabels = {
    'open': 'Open',
    'pending': 'In Progress',
    'resolved': 'Completed',
    'closed': 'Closed',
  };

  static const _priorities = {
    'low': 'Low',
    'medium': 'Medium',
    'high': 'High',
    'urgent': 'Urgent',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statuses = ticket.settableStatuses;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.build_outlined, size: 17, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'IT actions',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ],
          ),

          if (statuses.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Status',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final code in statuses.where((c) => c != 'resolved'))
                  ChoiceChip(
                    label: Text(_statusLabels[code] ?? code),
                    selected: _isCurrent(code),
                    onSelected: busy || _isCurrent(code)
                        ? null
                        : (_) => onStatus(code),
                  ),
              ],
            ),
            if (statuses.contains('resolved') && !_isCurrent('resolved')) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : onComplete,
                  icon: const Icon(Icons.task_alt_rounded, size: 19),
                  label: const Text('Write up and complete'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _isCurrent('resolved')
                    ? 'Waiting for the requester to confirm the fix.'
                    : 'Completing sends it back to the requester to confirm.',
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              ),
            ),
          ],

          if (ticket.canAssign) ...[
            const SizedBox(height: 16),
            Divider(color: scheme.outlineVariant, height: 1),
            const SizedBox(height: 14),
            Text(
              'Priority',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _priorities.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected:
                        ticket.priorityLabel.toLowerCase() == e.key,
                    onSelected: busy ? null : (_) => onPriority(e.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy ? null : onAssign,
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 19),
                label: Text(
                  (ticket.assignedTo == null || ticket.assignedTo!.isEmpty)
                      ? 'Assign to IT staff'
                      : 'Reassign (now ${ticket.assignedTo})',
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'Assigning and priority are set by the Super Admin.',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  bool _isCurrent(String code) =>
      ticket.statusLabel.toLowerCase() ==
      (_statusLabels[code] ?? code).toLowerCase();
}
