<?php
/**
 * Help desk tickets - raise one, follow it, reply, and sign the work off.
 *
 * The rules mirror the web app (ticket-new.php / ticket-view.php):
 *   - Super Admin and Admin see everything; Admin is read-only.
 *   - IT sees what is assigned to them, plus what they raised themselves.
 *   - Everyone else sees only their own tickets.
 *   - Only IT and the Super Admin change status, and never to "closed":
 *     a ticket is closed by the requester acknowledging the work.
 */
declare(strict_types=1);

/** How many photos one request may carry. */
const TICKET_MAX_PHOTOS = 5;

const TICKET_STATUS  = ['open' => 'Open', 'pending' => 'In Progress', 'resolved' => 'Completed', 'closed' => 'Closed'];
/** Statuses IT staff may set themselves. */
const TICKET_IT_SET  = ['open', 'pending', 'resolved'];
const TICKET_PRIO    = ['low' => 'Low', 'medium' => 'Medium', 'high' => 'High', 'urgent' => 'Urgent'];

/** Whoever may raise a ticket at all. */
function tickets_can_raise(array $u): bool {
    return in_array($u['role'], ['superadmin', 'employee', 'hr'], true);
}
/*
 * tickets_can_work() and tickets_it_designation() live in core.php, so
 * auth/me can report is_it_staff to the app.
 *
 * They are re-declared here behind function_exists() purely so this file still
 * runs against an older core.php: deployments do not always land both files at
 * once, and a missing helper is a fatal error that takes every ticket route
 * down. Keep the two definitions identical.
 */
if (!function_exists('tickets_it_designation')) {
    function tickets_it_designation(string $designation): bool {
        $words = ['IT', 'EDP', 'System', 'Systems', 'Network', 'Hardware', 'Software',
                  'Developer', 'Programmer', 'Technical', 'Tech', 'Support', 'Helpdesk'];
        $padded = ' ' . strtolower(str_replace(['.', '-', '/'], ' ', $designation)) . ' ';
        foreach ($words as $w) {
            if (strpos($padded, ' ' . strtolower($w) . ' ') !== false) return true;
        }
        return false;
    }
}

if (!function_exists('tickets_can_work')) {
    function tickets_can_work(array $u): bool {
        if (in_array($u['role'] ?? '', ['superadmin', 'it'], true)) return true;
        return ($u['department'] ?? '') === 'IT'
            || tickets_it_designation((string)($u['designation'] ?? ''));
    }
}

/** Admin is a reporting role: it reads tickets but never writes. */
function tickets_read_only(array $u): bool {
    return $u['role'] === 'admin';
}

/** The visibility rule, as SQL, for whichever user is asking. */
function tickets_scope(array $u): array {
    $uid = (int)$u['id'];
    if (in_array($u['role'], ['superadmin', 'admin'], true)) return ['1', '', []];
    // Anyone who does ticket work sees what is assigned to them as well as
    // what they raised. This has to ask tickets_can_work() rather than test
    // role === 'it': IT staff here are the IT *department*, whose accounts are
    // ordinary employees, and they could not see their own assigned tickets.
    if (tickets_can_work($u)) return ['(t.assigned_to = ? OR t.user_id = ?)', 'ii', [$uid, $uid]];
    return ['t.user_id = ?', 'i', [$uid]];
}

/** One ticket the caller is allowed to see, or a 404/403. */
function tickets_find(mysqli $conn, array $u, int $id): array {
    if ($id <= 0) fail('Pass the ticket id.', 422, 'validation_error');
    [$where, $types, $params] = tickets_scope($u);
    $row = fetch_one(
        $conn,
        "SELECT t.*, u.name AS requester_name, u.employee_id AS requester_code,
                a.name AS agent_name, d.name AS dept_name
           FROM tickets t
           JOIN users u ON u.id = t.user_id
           LEFT JOIN users a ON a.id = t.assigned_to
           LEFT JOIN departments d ON d.id = t.department_id
          WHERE t.id = ? AND $where LIMIT 1",
        'i' . $types,
        array_merge([$id], $params)
    );
    if (!$row) fail('Ticket not found, or it is not yours.', 404, 'not_found');
    return $row;
}

function shape_ticket(array $t, array $u = []): array {
    $mine = $u && (int)$t['user_id'] === (int)$u['id'];
    return [
        'id'              => (int)$t['id'],
        'code'            => $t['code'],
        'subject'         => $t['subject'],
        'body'            => $t['body'],
        'status'          => $t['status'],
        'status_label'    => TICKET_STATUS[$t['status']] ?? $t['status'],
        'priority'        => $t['priority'],
        'priority_label'  => TICKET_PRIO[$t['priority']] ?? $t['priority'],
        'location'        => $t['location'],
        'trained_before'  => $t['trained_before'],
        'user_id'         => (int)$t['user_id'],
        'requester_name'  => $t['requester_name'] ?? null,
        'requester_code'  => $t['requester_code'] ?? null,
        'assigned_to'     => $t['assigned_to'] !== null ? (int)$t['assigned_to'] : null,
        'agent_name'      => $t['agent_name'] ?? null,
        'department_id'   => $t['department_id'] !== null ? (int)$t['department_id'] : null,
        'department'      => $t['dept_name'] ?? null,
        'reopen_count'    => (int)$t['reopen_count'],
        'created_at'      => $t['created_at'],
        'updated_at'      => $t['updated_at'],
        'assigned_at'     => $t['assigned_at'],
        'completed_at'    => $t['completed_at'],
        'acknowledged_at' => $t['acknowledged_at'],
        'closed_at'       => $t['closed_at'],
        // What this caller may do next, so the app can draw the right buttons.
        'can_reply'       => !empty($u) && !tickets_read_only($u),
        'can_acknowledge' => $mine && $t['status'] === 'resolved',
        'can_reraise'     => $mine && in_array($t['status'], ['resolved', 'closed'], true),
        'can_update'      => !empty($u) && tickets_can_work($u),
        // Assigning, priority and department are the Super Admin's call; IT
        // staff move the status and reply. Sending these means the app never
        // has to guess which controls to draw.
        'can_assign'        => !empty($u) && ($u['role'] ?? '') === 'superadmin',
        'settable_statuses' => (!empty($u) && tickets_can_work($u)) ? TICKET_IT_SET : [],
    ];
}

/** The next TKT-yy-0001 code, skipping any that is taken. */
function tickets_next_code(mysqli $conn): string {
    $n = (int)fetch_value($conn, "SELECT COUNT(*) FROM tickets") + 1;
    do {
        $code = 'TKT-' . date('y') . '-' . str_pad((string)$n, 4, '0', STR_PAD_LEFT);
        $taken = fetch_one($conn, "SELECT id FROM tickets WHERE code = ? LIMIT 1", 's', [$code]);
        $n++;
    } while ($taken);
    return $code;
}

function tickets_log(mysqli $conn, int $ticketId, int $userId, string $action, string $detail = ''): void {
    $stmt = $conn->prepare("INSERT INTO ticket_activity (ticket_id, user_id, action, detail) VALUES (?,?,?,?)");
    $stmt->bind_param('iiss', $ticketId, $userId, $action, $detail);
    $stmt->execute();
    $stmt->close();
}

/** GET tickets - the caller's list. status?, search?, page, per_page. */
function tickets_index(mysqli $conn): void {
    $user = auth_user($conn);
    $p    = paging(20);

    [$where, $types, $params] = tickets_scope($user);

    $status = (string)param('status', '');
    if ($status !== '' && isset(TICKET_STATUS[$status])) {
        $where   .= ' AND t.status = ?';
        $types   .= 's';
        $params[] = $status;
    } elseif ($status === 'active') {          // everything not yet closed
        $where .= " AND t.status <> 'closed'";
    }
    // Who the ticket sits with: the IT app's "Assigned to me" section, and the
    // Super Admin's view of what nobody has picked up yet.
    $assigned = strtolower((string)param('assigned', ''));
    if ($assigned === 'me') {
        $where   .= ' AND t.assigned_to = ?';
        $types   .= 'i';
        $params[] = (int)$user['id'];
    } elseif ($assigned === 'unassigned' || $assigned === 'none') {
        $where .= ' AND t.assigned_to IS NULL';
    } elseif ($assigned === 'raised' || $assigned === 'mine') {
        $where   .= ' AND t.user_id = ?';
        $types   .= 'i';
        $params[] = (int)$user['id'];
    } elseif (ctype_digit($assigned) && (int)$assigned > 0) {
        $where   .= ' AND t.assigned_to = ?';
        $types   .= 'i';
        $params[] = (int)$assigned;
    }

    $q = (string)param('search', '');
    if ($q !== '') {
        $where   .= ' AND (t.subject LIKE ? OR t.code LIKE ?)';
        $types   .= 'ss';
        $like     = '%' . $q . '%';
        $params[] = $like;
        $params[] = $like;
    }

    $total = (int)fetch_value($conn, "SELECT COUNT(*) FROM tickets t WHERE $where", $types, $params);
    $rows  = fetch_all(
        $conn,
        "SELECT t.*, u.name AS requester_name, u.employee_id AS requester_code,
                a.name AS agent_name, d.name AS dept_name
           FROM tickets t
           JOIN users u ON u.id = t.user_id
           LEFT JOIN users a ON a.id = t.assigned_to
           LEFT JOIN departments d ON d.id = t.department_id
          WHERE $where
          ORDER BY t.updated_at DESC
          LIMIT ? OFFSET ?",
        $types . 'ii',
        array_merge($params, [$p['limit'], $p['offset']])
    );

    $counts = [];
    foreach (fetch_all($conn, "SELECT t.status, COUNT(*) n FROM tickets t WHERE $where GROUP BY t.status", $types, $params) as $r) {
        $counts[$r['status']] = (int)$r['n'];
    }

    ok(
        array_map(static fn(array $t): array => shape_ticket($t, $user), $rows),
        ['meta' => meta($p, $total) + ['counts' => $counts]]
    );
}

/** GET tickets/show?id= - one ticket with its conversation. */
function tickets_show(mysqli $conn): void {
    $user   = auth_user($conn);
    $ticket = tickets_find($conn, $user, param_int('id'));

    // Internal notes belong to the people working the ticket.
    $hideInternal = tickets_can_work($user) || tickets_read_only($user) ? '' : ' AND r.is_internal = 0';
    $replies = fetch_all(
        $conn,
        "SELECT r.id, r.message, r.is_internal, r.created_at, r.user_id, u.name AS author, u.role AS author_role
           FROM ticket_replies r JOIN users u ON u.id = r.user_id
          WHERE r.ticket_id = ?$hideInternal
          ORDER BY r.id",
        'i',
        [(int)$ticket['id']]
    );
    $activity = fetch_all(
        $conn,
        "SELECT a.action, a.detail, a.created_at, u.name AS author
           FROM ticket_activity a LEFT JOIN users u ON u.id = a.user_id
          WHERE a.ticket_id = ? ORDER BY a.id",
        'i',
        [(int)$ticket['id']]
    );

    ok([
        'ticket'      => shape_ticket($ticket, $user),
        'attachments' => tickets_attachments($conn, (int)$ticket['id']),
        'replies'  => array_map(static fn(array $r): array => [
            'id'          => (int)$r['id'],
            'message'     => $r['message'],
            'is_internal' => (bool)(int)$r['is_internal'],
            'user_id'     => (int)$r['user_id'],
            'author'      => $r['author'],
            'author_role' => $r['author_role'],
            'created_at'  => $r['created_at'],
        ], $replies),
        'activity' => array_map(static fn(array $a): array => [
            'action' => $a['action'], 'detail' => $a['detail'],
            'author' => $a['author'], 'created_at' => $a['created_at'],
        ], $activity),
    ]);
}

/** POST tickets/create { subject, body, location, trained_before } */
/**
 * Stores base64 photos sent by the app against a ticket or one of its replies,
 * in the same table and folder the web form writes to.
 *
 * Accepts a JSON array or a single string. Returns how many were kept.
 */
function tickets_store_photos(mysqli $conn, int $ticketId, ?int $replyId, $photos): int {
    if ($photos === null || $photos === '') return 0;
    if (is_string($photos)) $photos = [$photos];
    if (!is_array($photos)) return 0;

    $saved = 0;
    foreach (array_slice($photos, 0, TICKET_MAX_PHOTOS) as $i => $raw) {
        if (!is_string($raw) || $raw === '') continue;

        $file = store_base64_image($raw, UPLOAD_DIR);
        if ($file === null) {
            error_log('API v1: ticket ' . $ticketId . ' photo ' . $i . ' rejected');
            continue;
        }

        $name = 'photo_' . ($i + 1) . '.' . pathinfo($file['stored'], PATHINFO_EXTENSION);
        $stmt = $conn->prepare(
            "INSERT INTO attachments (ticket_id, reply_id, original_name, stored_name, mime, size_bytes)
             VALUES (?,?,?,?,?,?)"
        );
        $stmt->bind_param('iisssi', $ticketId, $replyId, $name, $file['stored'], $file['mime'], $file['size']);
        $stmt->execute();
        $stmt->close();
        $saved++;
    }
    return $saved;
}

/** Every attachment on a ticket, as signed links the app can show directly. */
function tickets_attachments(mysqli $conn, int $ticketId): array {
    $rows = fetch_all(
        $conn,
        "SELECT id, reply_id, original_name, stored_name, mime, size_bytes, created_at
           FROM attachments WHERE ticket_id = ? ORDER BY id",
        'i',
        [$ticketId]
    );
    return array_map(static fn(array $a): array => [
        'id'         => (int)$a['id'],
        'reply_id'   => $a['reply_id'] !== null ? (int)$a['reply_id'] : null,
        'name'       => $a['original_name'],
        'mime'       => $a['mime'],
        'size_bytes' => (int)$a['size_bytes'],
        'created_at' => $a['created_at'],
        'url'        => attachment_url($a['stored_name']),
    ], $rows);
}

function tickets_create(mysqli $conn): void {
    require_method('POST');
    $user = auth_user($conn);
    if (!tickets_can_raise($user)) {
        fail('Your account is not allowed to raise tickets.', 403, 'forbidden');
    }

    $in = require_params(['subject', 'body', 'location', 'trained_before']);

    if (mb_strlen($in['subject']) < 5)  fail('Subject must be at least 5 characters.', 422, 'validation_error');
    if (mb_strlen($in['body']) < 10)    fail('Describe the issue in at least 10 characters.', 422, 'validation_error');

    $trained = strtolower((string)$in['trained_before']);
    if (!in_array($trained, ['yes', 'no'], true)) {
        fail('trained_before must be "yes" or "no".', 422, 'validation_error');
    }
    // The location list is the HRMS master list (tickets/locations returns it).
    $known = fetch_one($conn, "SELECT name FROM locations WHERE name = ? LIMIT 1", 's', [$in['location']]);
    if (!$known) fail('Unknown location. Call tickets/locations for the list.', 422, 'validation_error');

    // The department is always the requester's own; it is never taken from the request.
    $deptId  = $user['department_id'] !== null ? (int)$user['department_id'] : null;
    $code    = tickets_next_code($conn);
    $subject = mb_substr((string)$in['subject'], 0, 200);
    $body    = (string)$in['body'];
    $uid     = (int)$user['id'];

    $stmt = $conn->prepare(
        "INSERT INTO tickets (code, subject, body, user_id, department_id, location, trained_before)
         VALUES (?,?,?,?,?,?,?)"
    );
    $stmt->bind_param('sssiiss', $code, $subject, $body, $uid, $deptId, $in['location'], $trained);
    if (!$stmt->execute()) {
        $stmt->close();
        fail('Could not create the ticket. Please try again.', 500, 'db_error');
    }
    $id = (int)$conn->insert_id;
    $stmt->close();

    tickets_log($conn, $id, $uid, 'created', 'Ticket opened');

    // Photos are optional and best-effort: a ticket that reached the database
    // is never lost because an image could not be decoded.
    $saved = tickets_store_photos($conn, $id, null, param('photos'));

    ok(['message' => 'Ticket ' . $code . ' has been created.',
        'photos_saved' => $saved,
        'ticket'  => shape_ticket(tickets_find($conn, $user, $id), $user)]);
}

/** POST tickets/reply { id, message, is_internal? } */
function tickets_reply(mysqli $conn): void {
    require_method('POST');
    $user = auth_user($conn);
    if (tickets_read_only($user)) fail('Admins have read-only access to tickets.', 403, 'forbidden');

    $ticket = tickets_find($conn, $user, param_int('id'));
    $in     = require_params(['message']);
    $msg    = (string)$in['message'];

    $internal = tickets_can_work($user) && (string)param('is_internal', '0') === '1' ? 1 : 0;
    $tid = (int)$ticket['id'];
    $uid = (int)$user['id'];

    $stmt = $conn->prepare("INSERT INTO ticket_replies (ticket_id, user_id, message, is_internal) VALUES (?,?,?,?)");
    $stmt->bind_param('iisi', $tid, $uid, $msg, $internal);
    if (!$stmt->execute()) {
        $stmt->close();
        fail('Could not post your reply.', 500, 'db_error');
    }
    $replyId = (int)$conn->insert_id;
    $stmt->close();

    $conn->query("UPDATE tickets SET updated_at = NOW() WHERE id = $tid");

    // Photos attach to this reply, so the conversation keeps them in order.
    $saved = tickets_store_photos($conn, $tid, $replyId, param('photos'));

    tickets_log($conn, $tid, $uid, 'replied', $internal ? 'Internal note added' : 'Reply added');

    ok(['message' => 'Reply posted.', 'reply_id' => $replyId, 'photos_saved' => $saved]);
}

/** POST tickets/update { id, status?, priority?, assigned_to?, department_id? } - IT and Super Admin. */
function tickets_update(mysqli $conn): void {
    require_method('POST', 'PATCH');
    $user = auth_user($conn);
    if (!tickets_can_work($user)) fail('Only IT staff and the Super Admin update tickets.', 403, 'forbidden');

    $ticket  = tickets_find($conn, $user, param_int('id'));
    $isSuper = $user['role'] === 'superadmin';

    $status = (string)param('status', $ticket['status']);
    if (!isset(TICKET_STATUS[$status])) fail('Unknown status.', 422, 'validation_error');
    // Closing belongs to the requester, through tickets/acknowledge.
    if ($status !== $ticket['status'] && !in_array($status, TICKET_IT_SET, true)) {
        fail('A ticket is closed by the person who raised it, once they acknowledge the work.', 422, 'closed_by_requester');
    }

    // Priority, assignee and department are the Super Admin's call.
    $priority = $isSuper ? (string)param('priority', $ticket['priority']) : $ticket['priority'];
    if (!isset(TICKET_PRIO[$priority])) fail('Unknown priority.', 422, 'validation_error');

    $wasAgent = (int)$ticket['assigned_to'];
    $agent    = $isSuper ? param_int('assigned_to', $wasAgent) : $wasAgent;
    $deptId   = $isSuper ? param_int('department_id', (int)$ticket['department_id']) : (int)$ticket['department_id'];

    if ($status === 'resolved' && !$agent) {
        fail('Assign the ticket to an IT person before marking it complete.', 422, 'validation_error');
    }
    if ($agent && !tickets_is_it_staff($conn, $agent)) {
        fail('Tickets can only be assigned to IT staff.', 422, 'validation_error');
    }

    $tid = (int)$ticket['id'];
    $stmt = $conn->prepare(
        "UPDATE tickets SET status = ?, priority = ?, assigned_to = ?, department_id = ?,
                assigned_at  = IF(? = 0, NULL, IF(? = ?, assigned_at, NOW())),
                completed_at = IF(? = 'resolved', COALESCE(completed_at, NOW()), NULL),
                closed_at    = NULL
          WHERE id = ?"
    );
    $agentOrNull = $agent ?: null;
    $deptOrNull  = $deptId ?: null;
    $stmt->bind_param('ssiiiiisi', $status, $priority, $agentOrNull, $deptOrNull,
                      $agent, $agent, $wasAgent, $status, $tid);
    if (!$stmt->execute()) {
        $stmt->close();
        fail('Could not update the ticket.', 500, 'db_error');
    }
    $stmt->close();

    $uid = (int)$user['id'];
    if ($status !== $ticket['status'])     tickets_log($conn, $tid, $uid, 'status', 'Status -> ' . TICKET_STATUS[$status]);
    if ($priority !== $ticket['priority']) tickets_log($conn, $tid, $uid, 'priority', 'Priority -> ' . TICKET_PRIO[$priority]);
    if ($agent !== $wasAgent) {
        $name = $agent ? (string)fetch_value($conn, "SELECT name FROM users WHERE id = ?", 'i', [$agent], '?') : 'nobody';
        tickets_log($conn, $tid, $uid, 'assigned', ($wasAgent ? 'Re-assigned to ' : 'Assigned to ') . $name);
    }
    if ($status === 'resolved' && $ticket['status'] !== 'resolved') {
        tickets_log($conn, $tid, $uid, 'completed', 'Marked complete - waiting for the requester to acknowledge');
    }

    ok(['message' => 'Ticket updated.', 'ticket' => shape_ticket(tickets_find($conn, $user, $tid), $user)]);
}

/** POST tickets/acknowledge { id } - the requester signs the work off and the ticket closes. */
function tickets_acknowledge(mysqli $conn): void {
    require_method('POST');
    $user   = auth_user($conn);
    $ticket = tickets_find($conn, $user, param_int('id'));

    if ((int)$ticket['user_id'] !== (int)$user['id']) {
        fail('Only the person who raised the ticket can acknowledge it.', 403, 'forbidden');
    }
    if ($ticket['status'] !== 'resolved') {
        fail('There is nothing waiting to be acknowledged on this ticket.', 422, 'nothing_to_acknowledge');
    }

    $tid = (int)$ticket['id'];
    $conn->query("UPDATE tickets SET status = 'closed', acknowledged_at = NOW(), closed_at = NOW() WHERE id = $tid");
    tickets_log($conn, $tid, (int)$user['id'], 'acknowledged', 'Requester acknowledged the work - ticket closed');

    ok(['message' => 'Thanks - the ticket is now closed.',
        'ticket'  => shape_ticket(tickets_find($conn, $user, $tid), $user)]);
}

/** POST tickets/reraise { id, reason? } - still broken: back to the assignment queue. */
function tickets_reraise(mysqli $conn): void {
    require_method('POST');
    $user   = auth_user($conn);
    $ticket = tickets_find($conn, $user, param_int('id'));

    if ((int)$ticket['user_id'] !== (int)$user['id']) {
        fail('Only the person who raised the ticket can send it back.', 403, 'forbidden');
    }
    if (!in_array($ticket['status'], ['resolved', 'closed'], true)) {
        fail('This ticket is already open.', 422, 'already_open');
    }

    $tid    = (int)$ticket['id'];
    $uid    = (int)$user['id'];
    $reason = (string)param('reason', '');

    $conn->query(
        "UPDATE tickets SET status = 'open', assigned_to = NULL, assigned_at = NULL,
                completed_at = NULL, acknowledged_at = NULL, closed_at = NULL,
                reopen_count = reopen_count + 1
          WHERE id = $tid"
    );
    if ($reason !== '') {
        $stmt = $conn->prepare("INSERT INTO ticket_replies (ticket_id, user_id, message, is_internal) VALUES (?,?,?,0)");
        $stmt->bind_param('iis', $tid, $uid, $reason);
        $stmt->execute();
        $stmt->close();
    }
    tickets_log($conn, $tid, $uid, 'reopened',
        'Requester marked it not resolved' . ($reason !== '' ? ' - ' . mb_substr($reason, 0, 160) : '')
        . ' - returned to the assignment queue');

    ok(['message' => 'Raised again - it is back with the Super Admin to be assigned.',
        'ticket'  => shape_ticket(tickets_find($conn, $user, $tid), $user)]);
}

/** May this employee be handed a ticket? The HRMS record decides. */
function tickets_is_it_staff(mysqli $conn, int $id): bool {
    $row = fetch_one(
        $conn,
        "SELECT u.role, u.designation, d.name AS department
           FROM users u LEFT JOIN departments d ON d.id = u.department_id
          WHERE u.id = ? AND u.is_active = 1 AND COALESCE(u.status,'Working') = 'Working' LIMIT 1",
        'i',
        [$id]
    );
    return $row !== null && tickets_can_work($row);
}

/** GET tickets/it_staff - who a ticket may be assigned to. */
function tickets_it_staff(mysqli $conn): void {
    $user = auth_user($conn);
    if (!tickets_can_work($user)) fail('Only IT staff and the Super Admin may assign tickets.', 403, 'forbidden');

    $rows = fetch_all(
        $conn,
        "SELECT u.id, u.name, u.employee_id, u.designation, d.name AS department
           FROM users u LEFT JOIN departments d ON d.id = u.department_id
          WHERE u.is_active = 1 AND COALESCE(u.status,'Working') = 'Working'
            AND u.role NOT IN ('admin','hod','face_operator')
          ORDER BY u.name"
    );
    $staff = array_values(array_filter($rows, static fn(array $r): bool => tickets_can_work($r)));
    ok(array_map(static fn(array $r): array => [
        'id' => (int)$r['id'], 'name' => $r['name'],
        'employee_id' => $r['employee_id'], 'designation' => $r['designation'],
        'department' => $r['department'],
    ], $staff));
}

/** GET tickets/locations - what the location field accepts, from the HRMS master list. */
function tickets_locations(mysqli $conn): void {
    auth_user($conn);
    $rows = fetch_all($conn, "SELECT name FROM locations ORDER BY name");
    ok(['locations' => array_column($rows, 'name'),
        'statuses'  => TICKET_STATUS,
        'priorities'=> TICKET_PRIO]);
}

/**
 * GET tickets/dashboard - what the IT dashboard needs in one call: the counts,
 * the one queue this person is expected to act on next, and the latest movement.
 * Mirrors dashboard.php on the web.
 */
function tickets_dashboard(mysqli $conn): void {
    $user = auth_user($conn);
    $uid  = (int)$user['id'];
    [$where, $types, $params] = tickets_scope($user);

    $c = fetch_one(
        $conn,
        "SELECT COUNT(*) total,
                SUM(t.status = 'open')     open_c,
                SUM(t.status = 'pending')  pending_c,
                SUM(t.status = 'resolved') resolved_c,
                SUM(t.status = 'closed')   closed_c,
                SUM(t.priority IN ('high','urgent') AND t.status <> 'closed') hot_c
           FROM tickets t WHERE $where",
        $types,
        $params
    ) ?: [];

    $select = "SELECT t.*, u.name AS requester_name, u.employee_id AS requester_code,
                      a.name AS agent_name, d.name AS dept_name
                 FROM tickets t
                 JOIN users u ON u.id = t.user_id
                 LEFT JOIN users a ON a.id = t.assigned_to
                 LEFT JOIN departments d ON d.id = t.department_id";

    /* The queue that matters to this caller:
         Super Admin / Admin - nobody has been given it yet
         IT                  - what is on their desk right now
         everyone else       - work marked complete, waiting for them to sign off */
    if (in_array($user['role'], ['superadmin', 'admin'], true)) {
        $queueTitle = 'Waiting to be assigned';
        $queue = fetch_all($conn, "$select WHERE t.assigned_to IS NULL AND t.status <> 'closed'
                                    ORDER BY t.created_at ASC LIMIT 50");
    } elseif (tickets_can_work($user)) {
        $queueTitle = 'On your desk';
        $queue = fetch_all($conn, "$select WHERE t.assigned_to = ? AND t.status IN ('open','pending')
                                    ORDER BY FIELD(t.priority,'urgent','high','medium','low'), t.created_at ASC LIMIT 50",
                           'i', [$uid]);
    } else {
        $queueTitle = 'Waiting for your acknowledgement';
        $queue = fetch_all($conn, "$select WHERE t.user_id = ? AND t.status = 'resolved'
                                    ORDER BY t.completed_at DESC LIMIT 50", 'i', [$uid]);
    }

    $recent = fetch_all($conn, "$select WHERE $where ORDER BY t.updated_at DESC LIMIT 8", $types, $params);

    ok([
        'counts' => [
            'total'     => (int)($c['total'] ?? 0),
            'open'      => (int)($c['open_c'] ?? 0),
            'pending'   => (int)($c['pending_c'] ?? 0),
            'resolved'  => (int)($c['resolved_c'] ?? 0),
            'closed'    => (int)($c['closed_c'] ?? 0),
            'high_open' => (int)($c['hot_c'] ?? 0),
        ],
        'queue'      => ['title'   => $queueTitle,
                         'tickets' => array_map(static fn(array $t): array => shape_ticket($t, $user), $queue)],
        'recent'     => array_map(static fn(array $t): array => shape_ticket($t, $user), $recent),
        'can_assign' => $user['role'] === 'superadmin',
        'can_work'   => tickets_can_work($user),
    ]);
}

/**
 * POST tickets/assign { id, assigned_to, priority? } - hand a ticket to an IT
 * person, or take it back with assigned_to = 0. Super Admin only, as on the web.
 */
function tickets_assign(mysqli $conn): void {
    require_method('POST');
    $user = auth_user($conn);
    if ($user['role'] !== 'superadmin') fail('Only the Super Admin assigns tickets.', 403, 'forbidden');

    $ticket = tickets_find($conn, $user, param_int('id'));
    $agent  = param_int('assigned_to');
    $was    = $ticket['assigned_to'] !== null ? (int)$ticket['assigned_to'] : 0;

    if ($agent && !tickets_is_it_staff($conn, $agent)) {
        fail('Tickets can only be assigned to IT staff. Call tickets/it_staff for the list.', 422, 'validation_error');
    }

    $priority = (string)param('priority', $ticket['priority']);
    if (!isset(TICKET_PRIO[$priority])) fail('Unknown priority.', 422, 'validation_error');

    // assigned_at marks when it landed on somebody's desk, so it only moves on a change.
    $stamp = $agent === 0 ? 'NULL' : ($agent !== $was ? 'NOW()' : 'assigned_at');
    $tid   = (int)$ticket['id'];
    $agentOrNull = $agent ?: null;

    $stmt = $conn->prepare("UPDATE tickets SET assigned_to = ?, priority = ?, assigned_at = $stamp WHERE id = ?");
    $stmt->bind_param('isi', $agentOrNull, $priority, $tid);
    if (!$stmt->execute()) { $stmt->close(); fail('Could not assign the ticket.', 500, 'db_error'); }
    $stmt->close();

    if ($agent !== $was) {
        $name = $agent ? (string)fetch_value($conn, "SELECT name FROM users WHERE id = ?", 'i', [$agent], '?') : 'nobody';
        tickets_log($conn, $tid, (int)$user['id'], 'assigned', ($was ? 'Re-assigned to ' : 'Assigned to ') . $name);
    }
    if ($priority !== $ticket['priority']) {
        tickets_log($conn, $tid, (int)$user['id'], 'priority', 'Priority -> ' . TICKET_PRIO[$priority]);
    }

    ok(['message' => $agent ? 'Ticket assigned.' : 'Ticket returned to the queue.',
        'ticket'  => shape_ticket(tickets_find($conn, $user, $tid), $user)]);
}

/** The assignee records what they did; the Super Admin may too. */
function tickets_can_log_work(array $user, array $ticket): bool {
    return $user['role'] === 'superadmin'
        || (tickets_can_work($user) && (int)$ticket['assigned_to'] === (int)$user['id']);
}

/** GET tickets/worklog?id= - the work recorded against one ticket. */
function tickets_worklog(mysqli $conn): void {
    $user   = auth_user($conn);
    $ticket = tickets_find($conn, $user, param_int('id'));
    $rows   = fetch_all(
        $conn,
        "SELECT w.id, w.work_date, w.summary, w.details, w.hours, w.created_at, w.user_id, u.name AS author
           FROM ticket_work_logs w JOIN users u ON u.id = w.user_id
          WHERE w.ticket_id = ? ORDER BY w.work_date DESC, w.id DESC",
        'i',
        [(int)$ticket['id']]
    );
    ok([
        'entries' => array_map(static fn(array $r): array => [
            'id'      => (int)$r['id'],  'work_date' => $r['work_date'], 'summary' => $r['summary'],
            'details' => $r['details'],  'hours'     => (float)$r['hours'],
            'user_id' => (int)$r['user_id'], 'author' => $r['author'], 'created_at' => $r['created_at'],
        ], $rows),
        'total_hours' => round(array_sum(array_map(static fn(array $r): float => (float)$r['hours'], $rows)), 2),
        'can_add'     => tickets_can_log_work($user, $ticket),
    ]);
}

/** POST tickets/log_work { id, summary, work_date?, hours?, details? } */
function tickets_log_work(mysqli $conn): void {
    require_method('POST');
    $user   = auth_user($conn);
    $ticket = tickets_find($conn, $user, param_int('id'));
    if (!tickets_can_log_work($user, $ticket)) {
        fail('Only the person the ticket is assigned to records work on it.', 403, 'forbidden');
    }

    $in      = require_params(['summary']);
    $summary = mb_substr((string)$in['summary'], 0, 200);
    if (mb_strlen($summary) < 3) fail('Describe the work in at least 3 characters.', 422, 'validation_error');

    $date = (string)param('work_date', date('Y-m-d'));
    if (!valid_date($date) || $date > date('Y-m-d')) {
        fail('Pick a valid work date - future dates are not allowed.', 422, 'validation_error');
    }
    $hours   = max(0.0, min(24.0, (float)param('hours', 0)));
    $d       = param('details');
    $details = ($d !== null && $d !== '') ? (string)$d : null;
    $tid     = (int)$ticket['id'];
    $uid     = (int)$user['id'];

    $stmt = $conn->prepare("INSERT INTO ticket_work_logs (ticket_id, user_id, work_date, summary, details, hours)
                            VALUES (?,?,?,?,?,?)");
    $stmt->bind_param('iisssd', $tid, $uid, $date, $summary, $details, $hours);
    if (!$stmt->execute()) { $stmt->close(); fail('Could not save the work entry.', 500, 'db_error'); }
    $id = (int)$conn->insert_id;
    $stmt->close();

    $conn->query("UPDATE tickets SET updated_at = NOW() WHERE id = $tid");
    tickets_log($conn, $tid, $uid, 'work_logged', 'Work logged: ' . mb_substr($summary, 0, 180));

    ok(['message' => 'Work entry saved.', 'id' => $id]);
}

/** POST tickets/delete_work { id } - authors remove their own; the Super Admin any. */
function tickets_delete_work(mysqli $conn): void {
    require_method('POST', 'DELETE');
    $user  = auth_user($conn);
    $entry = param_int('id');
    if (!$entry) fail('Pass the work entry id.', 422, 'validation_error');

    $sql   = "DELETE FROM ticket_work_logs WHERE id = ?";
    $types = 'i';
    $args  = [$entry];
    if ($user['role'] !== 'superadmin') { $sql .= " AND user_id = ?"; $types .= 'i'; $args[] = (int)$user['id']; }

    $stmt = $conn->prepare($sql);
    $stmt->bind_param($types, ...$args);
    $stmt->execute();
    $gone = $stmt->affected_rows;
    $stmt->close();

    if (!$gone) fail('That work entry is not yours to remove.', 403, 'forbidden');
    ok(['message' => 'Work entry removed.']);
}
