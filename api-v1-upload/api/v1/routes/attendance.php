<?php
/**
 * Attendance endpoints - punching, history, summary, live location.
 * Punch rules mirror employee/punch_in.php and employee/punch_out.php:
 * server time is authoritative and multiple in/out pairs per day are allowed.
 */
declare(strict_types=1);

/** GET attendance/today - every punch of the current attendance day. */
function attendance_today(mysqli $conn): void {
    $user = auth_user($conn);
    $uid  = target_user_id($user);
    $date = attendance_date();

    $rows = fetch_all(
        $conn,
        "SELECT * FROM attendance WHERE user_id = ? AND date = ? ORDER BY id ASC",
        'is',
        [$uid, $date]
    );

    $punches = array_map('shape_attendance', $rows);
    $worked  = 0;
    $open    = null;
    foreach ($punches as $p) {
        $worked += (int)($p['worked_minutes'] ?? 0);
        if ($p['punch_out'] === null) $open = $p;
    }

    ok([
        'date'             => $date,
        'server_time'      => date('Y-m-d H:i:s'),
        'is_punched_in'    => $open !== null,
        'open_punch'       => $open,
        'can_punch_in'     => $open === null,
        'can_punch_out'    => $open !== null,
        'total_punches'    => count($punches),
        'worked_minutes'   => $worked,
        'worked_hours'     => hhmm($worked),
        'first_punch_in'   => $punches[0]['punch_in'] ?? null,
        'last_punch_out'   => $punches ? end($punches)['punch_out'] : null,
        'punches'          => $punches,
    ]);
}

/** POST attendance/punch_in { selfie_image, latitude, longitude, accuracy? } */
function attendance_punch_in(mysqli $conn): void {
    require_method('POST');
    $user = auth_user($conn);
    $uid  = (int)$user['id'];

    if (in_array($user['role'], ['superadmin', 'admin', 'hod', 'face_operator'], true)) {
        fail('Super Admin and Admin accounts do not record attendance.', 403, 'forbidden');
    }
    if (($user['status'] ?? '') === 'Resign') {
        fail('Your account has been marked as Resign. You cannot punch in.', 403, 'account_inactive');
    }

    $lat = param_float('latitude')  ?? param_float('punch_in_lat');
    $lng = param_float('longitude') ?? param_float('punch_in_lng');
    $acc = param_float('accuracy')  ?? param_float('punch_in_accuracy');

    $geo = check_location_allowed($conn, $uid, $lat, $lng);
    if (!$geo['allowed']) {
        fail($geo['message'], 403, 'outside_geofence', ['distance_meters' => $geo['distance'] ?? null]);
    }

    // One open punch at a time - the app must punch out before punching in again.
    $date = attendance_date();
    $open = fetch_one(
        $conn,
        "SELECT id, punch_in FROM attendance WHERE user_id = ? AND date = ? AND punch_out IS NULL ORDER BY id DESC LIMIT 1",
        'is',
        [$uid, $date]
    );
    if ($open) {
        fail('You are already punched in at ' . $open['punch_in'] . '. Please punch out first.', 409, 'already_punched_in',
             ['open_punch_id' => (int)$open['id']]);
    }

    $selfie = save_selfie((string)(param('selfie_image') ?? param('selfie') ?? ''), $uid, 'selfie');
    if (!$selfie['ok']) fail($selfie['message'], 422, 'selfie_error');

    // Server time only - a device clock can never set the punch time.
    $time     = date('H:i:s');
    $location = location_name($lat, $lng);

    $stmt = $conn->prepare(
        "INSERT INTO attendance
            (user_id, date, punch_in, status, selfie_punchin, punch_in_location,
             punch_in_lat, punch_in_lng, punch_in_accuracy, punch_in_by)
         VALUES (?, ?, ?, 'Present', ?, ?, ?, ?, ?, ?)"
    );
    $stmt->bind_param('issssdddi', $uid, $date, $time, $selfie['filename'], $location, $lat, $lng, $acc, $uid);

    if (!$stmt->execute()) {
        $err = $stmt->error;
        $stmt->close();
        error_log("API punch_in failed for user {$uid}: {$err}");
        if (stripos($err, 'duplicate') !== false || stripos($err, 'unique_daily_attendance') !== false) {
            fail('The database still enforces one punch per day. Ask your admin to run admin/setup.php.', 409, 'db_constraint');
        }
        fail('Could not save your punch in. Please try again.', 500, 'db_error');
    }
    $id = (int)$conn->insert_id;
    $stmt->close();

    error_log("API PUNCH_IN: user {$uid} at {$time} on {$date} (record {$id})");

    $row = fetch_one($conn, "SELECT * FROM attendance WHERE id = ?", 'i', [$id]);
    ok([
        'message'    => 'Punch in recorded at ' . $time . '.',
        'attendance' => shape_attendance($row),
        'distance_meters' => $geo['distance'] ?? null,
    ]);
}

/** POST attendance/punch_out { selfie_image, latitude, longitude, accuracy? } */
function attendance_punch_out(mysqli $conn): void {
    require_method('POST');
    $user = auth_user($conn);
    $uid  = (int)$user['id'];

    if (in_array($user['role'], ['superadmin', 'admin', 'hod', 'face_operator'], true)) {
        fail('Super Admin and Admin accounts do not record attendance.', 403, 'forbidden');
    }
    if (($user['status'] ?? '') === 'Resign') {
        fail('Your account has been marked as Resign. You cannot punch out.', 403, 'account_inactive');
    }

    $lat = param_float('latitude')  ?? param_float('punch_out_lat');
    $lng = param_float('longitude') ?? param_float('punch_out_lng');
    $acc = param_float('accuracy')  ?? param_float('punch_out_accuracy');

    $geo = check_location_allowed($conn, $uid, $lat, $lng);
    if (!$geo['allowed']) {
        fail($geo['message'], 403, 'outside_geofence', ['distance_meters' => $geo['distance'] ?? null]);
    }

    $date = attendance_date();
    $open = fetch_one(
        $conn,
        "SELECT id, punch_in FROM attendance WHERE user_id = ? AND date = ? AND punch_out IS NULL ORDER BY id DESC LIMIT 1",
        'is',
        [$uid, $date]
    );
    if (!$open) {
        fail('No open punch in found for today. Please punch in first.', 409, 'not_punched_in');
    }

    $selfie = save_selfie((string)(param('selfie_image') ?? param('selfie') ?? ''), $uid, 'selfie_punchout');
    if (!$selfie['ok']) fail($selfie['message'], 422, 'selfie_error');

    $time     = date('H:i:s');
    $location = location_name($lat, $lng);
    $id       = (int)$open['id'];

    $stmt = $conn->prepare(
        "UPDATE attendance
            SET punch_out = ?, selfie_punchout = ?, punch_out_location = ?,
                punch_out_lat = ?, punch_out_lng = ?, punch_out_accuracy = ?, punch_out_by = ?
          WHERE id = ? AND punch_out IS NULL"
    );
    $stmt->bind_param('sssdddii', $time, $selfie['filename'], $location, $lat, $lng, $acc, $uid, $id);
    $stmt->execute();
    $changed = $stmt->affected_rows;
    $stmt->close();

    if ($changed < 1) {
        fail('That punch was already closed. Please refresh and try again.', 409, 'already_punched_out');
    }

    $distance_km = attendance_store_route($conn, $uid, $id, $date);
    error_log("API PUNCH_OUT: user {$uid} at {$time} on {$date} (record {$id}, {$distance_km} km)");

    $row = fetch_one($conn, "SELECT * FROM attendance WHERE id = ?", 'i', [$id]);
    ok([
        'message'           => 'Punch out recorded at ' . $time . '.',
        'attendance'        => shape_attendance($row),
        'distance_km'       => $distance_km,
        'distance_meters'   => $geo['distance'] ?? null,
    ]);
}

/**
 * Rolls the session's tracked points into route_summary and returns the
 * travelled distance in km. Same computation as employee/punch_out.php.
 */
function attendance_store_route(mysqli $conn, int $uid, int $punch_id, string $date): float {
    $points = fetch_all(
        $conn,
        "SELECT latitude, longitude FROM location_tracking
          WHERE user_id = ? AND punch_in_id = ? ORDER BY timestamp ASC",
        'ii',
        [$uid, $punch_id]
    );
    if (count($points) < 2) return 0.0;

    $coords = array_map(static function (array $p): array {
        return ['latitude' => (float)$p['latitude'], 'longitude' => (float)$p['longitude']];
    }, $points);

    $meters = 0.0;
    for ($i = 0, $n = count($coords) - 1; $i < $n; $i++) {
        $meters += haversine_m(
            $coords[$i]['latitude'], $coords[$i]['longitude'],
            $coords[$i + 1]['latitude'], $coords[$i + 1]['longitude']
        );
    }
    $km = round($meters / 1000, 2);

    $json = json_encode($coords, JSON_UNESCAPED_SLASHES);
    $stmt = $conn->prepare(
        "INSERT INTO route_summary (user_id, punch_in_id, total_distance_km, route_data, date)
         VALUES (?, ?, ?, ?, ?)"
    );
    $stmt->bind_param('iidss', $uid, $punch_id, $km, $json, $date);
    $stmt->execute();
    $stmt->close();

    return $km;
}

/** GET attendance/history - paged punches for a month or from/to range. */
function attendance_history(mysqli $conn): void {
    $user = auth_user($conn);
    $uid  = target_user_id($user);
    [$from, $to] = date_range();
    $p = paging(50);

    $total = (int)fetch_value(
        $conn,
        "SELECT COUNT(*) FROM attendance WHERE user_id = ? AND date BETWEEN ? AND ?",
        'iss',
        [$uid, $from, $to]
    );

    $rows = fetch_all(
        $conn,
        "SELECT * FROM attendance
          WHERE user_id = ? AND date BETWEEN ? AND ?
          ORDER BY date DESC, id DESC
          LIMIT ? OFFSET ?",
        'issii',
        [$uid, $from, $to, $p['limit'], $p['offset']]
    );

    ok(array_map('shape_attendance', $rows), [
        'range' => ['from' => $from, 'to' => $to],
        'meta'  => meta($p, $total),
    ]);
}

/**
 * GET attendance/summary - one entry per calendar day in the range, with the
 * day's first punch in, last punch out, total worked time and day type.
 */
function attendance_summary(mysqli $conn): void {
    $user = auth_user($conn);
    $uid  = target_user_id($user);
    [$from, $to] = date_range();

    $rows = fetch_all(
        $conn,
        "SELECT * FROM attendance WHERE user_id = ? AND date BETWEEN ? AND ? ORDER BY date ASC, id ASC",
        'iss',
        [$uid, $from, $to]
    );

    $od = array_column(fetch_all(
        $conn,
        "SELECT od_date FROM od_records WHERE user_id = ? AND od_date BETWEEN ? AND ?",
        'iss',
        [$uid, $from, $to]
    ), 'od_date');

    $comp_off = array_column(fetch_all(
        $conn,
        "SELECT comp_off_date FROM comp_off_requests WHERE user_id = ? AND comp_off_date BETWEEN ? AND ?",
        'iss',
        [$uid, $from, $to]
    ), 'comp_off_date');

    $leaves = fetch_all(
        $conn,
        "SELECT leave_type, start_date, end_date FROM leave_applications
          WHERE user_id = ? AND status = 'Approved' AND start_date <= ? AND end_date >= ?",
        'iss',
        [$uid, $to, $from]
    );

    $holidays = array_column(fetch_all(
        $conn,
        "SELECT holiday_date FROM project_holidays WHERE holiday_date BETWEEN ? AND ?",
        'ss',
        [$from, $to]
    ), 'holiday_date');

    $week_off = $user['week_off'] ?? null;
    if ((int)$uid !== (int)$user['id']) {
        $other = fetch_one($conn, "SELECT week_off FROM users WHERE id = ?", 'i', [$uid]);
        $week_off = $other['week_off'] ?? null;
    }

    // Group punches by day.
    $days = [];
    foreach ($rows as $r) {
        $d = $r['date'];
        if (!isset($days[$d])) {
            $days[$d] = ['date' => $d, 'punches' => [], 'worked_minutes' => 0];
        }
        $shaped = shape_attendance($r);
        $days[$d]['punches'][] = $shaped;
        $days[$d]['worked_minutes'] += (int)($shaped['worked_minutes'] ?? 0);
    }

    $out = [];
    $stats = ['present' => 0, 'absent' => 0, 'leave' => 0, 'od' => 0, 'comp_off' => 0,
              'holiday' => 0, 'week_off' => 0, 'worked_minutes' => 0, 'incomplete' => 0];

    for ($ts = strtotime($from), $end = strtotime($to); $ts <= $end; $ts = strtotime('+1 day', $ts)) {
        $d   = date('Y-m-d', $ts);
        $day = $days[$d] ?? ['date' => $d, 'punches' => [], 'worked_minutes' => 0];

        $leave_type = null;
        foreach ($leaves as $l) {
            if ($d >= $l['start_date'] && $d <= $l['end_date']) { $leave_type = $l['leave_type']; break; }
        }

        $type = 'Absent';
        if ($day['punches'])                          $type = 'Present';
        elseif (in_array($d, $od, true))              $type = 'OD';
        elseif (in_array($d, $comp_off, true))        $type = 'Comp Off';
        elseif ($leave_type !== null)                 $type = 'Leave';
        elseif (in_array($d, $holidays, true))        $type = 'Holiday';
        elseif ($week_off && date('l', $ts) === $week_off) $type = 'Week Off';

        $incomplete = false;
        foreach ($day['punches'] as $pch) {
            if ($pch['punch_out'] === null) { $incomplete = true; break; }
        }

        // Days in the future are not counted as absent.
        $is_future = $d > date('Y-m-d');

        $out[] = [
            'date'           => $d,
            'day'            => date('l', $ts),
            'type'           => $is_future && $type === 'Absent' ? 'Upcoming' : $type,
            'leave_type'     => $leave_type,
            'punch_in'       => $day['punches'][0]['punch_in'] ?? null,
            'punch_out'      => $day['punches'] ? end($day['punches'])['punch_out'] : null,
            'punch_count'    => count($day['punches']),
            'incomplete'     => $incomplete,
            'worked_minutes' => $day['worked_minutes'],
            'worked_hours'   => hhmm($day['worked_minutes']),
            'punches'        => $day['punches'],
        ];

        if ($is_future && $type === 'Absent') continue;
        $stats['worked_minutes'] += $day['worked_minutes'];
        if ($incomplete) $stats['incomplete']++;
        switch ($type) {
            case 'Present':  $stats['present']++;  break;
            case 'OD':       $stats['od']++;       break;
            case 'Comp Off': $stats['comp_off']++; break;
            case 'Leave':    $stats['leave']++;    break;
            case 'Holiday':  $stats['holiday']++;  break;
            case 'Week Off': $stats['week_off']++; break;
            default:         $stats['absent']++;
        }
    }

    $stats['payable_days'] = $stats['present'] + $stats['od'] + $stats['comp_off']
                           + $stats['leave'] + $stats['holiday'] + $stats['week_off'];
    $stats['worked_hours'] = hhmm($stats['worked_minutes']);

    ok([
        'range' => ['from' => $from, 'to' => $to],
        'stats' => $stats,
        'days'  => $out,
    ]);
}

/** POST attendance/track - background GPS ping while punched in. */
function attendance_track(mysqli $conn): void {
    require_method('POST');
    $user = auth_user($conn);
    $uid  = (int)$user['id'];

    $lat = param_float('latitude');
    $lng = param_float('longitude');
    if ($lat === null || $lng === null) {
        fail('latitude and longitude are required.', 422, 'validation_error');
    }

    $date = attendance_date();
    $open = fetch_one(
        $conn,
        "SELECT id FROM attendance WHERE user_id = ? AND date = ? AND punch_out IS NULL ORDER BY id DESC LIMIT 1",
        'is',
        [$uid, $date]
    );
    if (!$open) fail('No active punch in - tracking is not recorded.', 409, 'not_punched_in');

    $acc     = param_float('accuracy');
    $address = param('address');
    if ($address === null || $address === '') $address = 'Lat: ' . number_format($lat, 4) . ', Lng: ' . number_format($lng, 4);
    $address = mb_substr((string)$address, 0, 255);
    $punch_id = (int)$open['id'];

    $stmt = $conn->prepare(
        "INSERT INTO location_tracking (user_id, punch_in_id, latitude, longitude, accuracy, address, timestamp)
         VALUES (?, ?, ?, ?, ?, ?, NOW())"
    );
    $stmt->bind_param('iiddds', $uid, $punch_id, $lat, $lng, $acc, $address);
    $stmt->execute();
    $id = (int)$conn->insert_id;
    $stmt->close();

    ok(['tracked' => true, 'id' => $id, 'punch_in_id' => $punch_id]);
}

/** GET attendance/route - tracked points + summary for one punch session. */
function attendance_route(mysqli $conn): void {
    $user = auth_user($conn);
    $uid  = target_user_id($user);
    $punch_id = param_int('id') ?: param_int('punch_in_id');
    if (!$punch_id) fail('punch_in_id is required.', 422, 'validation_error');

    $record = fetch_one($conn, "SELECT * FROM attendance WHERE id = ? AND user_id = ?", 'ii', [$punch_id, $uid]);
    if (!$record) fail('Punch record not found.', 404, 'not_found');

    $points = fetch_all(
        $conn,
        "SELECT latitude, longitude, accuracy, address, timestamp FROM location_tracking
          WHERE user_id = ? AND punch_in_id = ? ORDER BY timestamp ASC",
        'ii',
        [$uid, $punch_id]
    );

    $summary = fetch_one(
        $conn,
        "SELECT total_distance_km, travel_time, start_location, end_location, date
           FROM route_summary WHERE punch_in_id = ? ORDER BY id DESC LIMIT 1",
        'i',
        [$punch_id]
    );

    ok([
        'attendance' => shape_attendance($record),
        'distance_km' => $summary ? (float)$summary['total_distance_km'] : 0.0,
        'summary'    => $summary,
        'points'     => array_map(static function (array $p): array {
            return [
                'latitude'  => (float)$p['latitude'],
                'longitude' => (float)$p['longitude'],
                'accuracy'  => $p['accuracy'] !== null ? (float)$p['accuracy'] : null,
                'address'   => $p['address'],
                'timestamp' => $p['timestamp'],
            ];
        }, $points),
    ]);
}
