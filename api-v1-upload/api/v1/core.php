<?php
/**
 * Mobile API core - bootstrap, auth, helpers.
 * Every request to api/v1/ passes through here via index.php.
 */
declare(strict_types=1);

date_default_timezone_set('Asia/Kolkata');
mb_internal_encoding('UTF-8');

// API returns JSON only; never leak HTML warnings into the body.
ini_set('display_errors', '0');
error_reporting(E_ALL);

define('API_ROOT', __DIR__);
define('APP_ROOT', dirname(__DIR__, 2));
define('TOKEN_TTL_DAYS', 30);

// One database with the ticket system: same config, same users table.
require_once APP_ROOT . '/includes/config.php';
date_default_timezone_set('Asia/Kolkata');
ini_set('display_errors', '0');

// APP_KEY signs the expiring file links. A deployment whose config predates it
// would otherwise take down every endpoint that returns a selfie or photo: in
// PHP 8 an undefined constant is a fatal Error, not a notice, so the failure
// arrives as an opaque 500 far from its cause.
//
// Derive a stable per-install fallback instead. Signing and verifying then
// still agree with each other, links keep working, and the log says what to
// fix. Set a real APP_KEY in includes/config.php: the fallback is predictable
// from values that are not secret.
if (!defined('APP_KEY')) {
    error_log('API v1: APP_KEY is not defined in includes/config.php - '
        . 'falling back to a derived key. Add a random APP_KEY to that file.');
    define('APP_KEY', hash('sha256', 'hrms-api-v1|' . APP_ROOT . '|' . DB_NAME));
}
define('UPLOAD_BASE', UPLOAD_DIR . '/hrms'); // not web-reachable; files go out through files/*

mysqli_report(MYSQLI_REPORT_OFF);
$conn = @new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);
if ($conn->connect_error) {
    http_response_code(503);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['success' => false, 'code' => 'server_error', 'message' => 'Database unavailable.']);
    exit;
}
$conn->set_charset('utf8mb4');

/**
 * users.department became users.department_id when the HRMS joined the ticket
 * system. Queries that report a department name read it through this.
 */
const DEPT_SQL = '(SELECT dd.name FROM departments dd WHERE dd.id = u.department_id)';

/** Roles that record attendance (not the Super Admin, Admins or the kiosk account). */
const STAFF_SQL = "u.role NOT IN ('superadmin','admin','hod','face_operator') AND u.phone IS NOT NULL";

// ---------------------------------------------------------------- responses

function json_out(array $payload, int $status = 200): void {
    if (!headers_sent()) {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        header('Cache-Control: no-store');
    }
    echo json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

function ok($data = null, array $extra = []): void {
    json_out(['success' => true] + $extra + ['data' => $data]);
}

function fail(string $message, int $status = 400, string $code = 'error', array $extra = []): void {
    json_out(['success' => false, 'code' => $code, 'message' => $message] + $extra, $status);
}

// ---------------------------------------------------------------- input

/** Merged request body: JSON, form-encoded or query string. */
function input(): array {
    static $data = null;
    if ($data !== null) return $data;

    $data = $_GET;
    $raw  = file_get_contents('php://input');
    if ($raw !== '' && $raw !== false) {
        $decoded = json_decode($raw, true);
        if (is_array($decoded)) $data = array_merge($data, $decoded);
    }
    if (!empty($_POST)) $data = array_merge($data, $_POST);
    return $data;
}

function param(string $key, $default = null) {
    $v = input()[$key] ?? $default;
    return is_string($v) ? trim($v) : $v;
}

function param_int(string $key, int $default = 0): int { return (int)param($key, $default); }

function param_float(string $key): ?float {
    $v = param($key);
    return ($v === null || $v === '') ? null : (float)$v;
}

function require_params(array $keys): array {
    $out = [];
    $missing = [];
    foreach ($keys as $k) {
        $v = param($k);
        if ($v === null || $v === '') { $missing[] = $k; continue; }
        $out[$k] = $v;
    }
    if ($missing) fail('Missing required field(s): ' . implode(', ', $missing), 422, 'validation_error');
    return $out;
}

function require_method(string ...$methods): void {
    if (!in_array($_SERVER['REQUEST_METHOD'], $methods, true)) {
        fail('Method not allowed. Use ' . implode('/', $methods) . '.', 405, 'method_not_allowed');
    }
}

// ---------------------------------------------------------------- auth

/** Bearer token from header, or `token` in the body (fallback for simple clients). */
function bearer_token(): ?string {
    $hdr = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    if ($hdr === '' && function_exists('apache_request_headers')) {
        foreach (apache_request_headers() as $k => $v) {
            if (strcasecmp($k, 'Authorization') === 0) { $hdr = $v; break; }
        }
    }
    if (preg_match('/Bearer\s+(\S+)/i', (string)$hdr, $m)) return $m[1];
    $t = param('token');
    return ($t !== null && $t !== '') ? (string)$t : null;
}

function issue_token(mysqli $conn, int $user_id, string $device = ''): array {
    $token   = bin2hex(random_bytes(32));
    $expires = date('Y-m-d H:i:s', strtotime('+' . TOKEN_TTL_DAYS . ' days'));
    $device  = mb_substr($device, 0, 255);
    $stmt = $conn->prepare(
        "INSERT INTO auth_tokens (user_id, token, device_info, created_at, expires_at) VALUES (?, ?, ?, NOW(), ?)"
    );
    $stmt->bind_param('isss', $user_id, $token, $device, $expires);
    $stmt->execute();
    $stmt->close();
    return ['token' => $token, 'expires_at' => $expires];
}

/** Resolves the caller, or ends the request with 401. Extends the token on use. */
function auth_user(mysqli $conn): array {
    static $user = null;
    if ($user !== null) return $user;

    $token = bearer_token();
    if (!$token) fail('Authentication required. Send an Authorization: Bearer <token> header.', 401, 'unauthenticated');

    $stmt = $conn->prepare(
        "SELECT t.id AS token_id, t.expires_at, u.*, " . DEPT_SQL . " AS department
           FROM auth_tokens t
           JOIN users u ON u.id = t.user_id
          WHERE t.token = ? LIMIT 1"
    );
    $stmt->bind_param('s', $token);
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$row) fail('Invalid token. Please log in again.', 401, 'invalid_token');
    if (strtotime($row['expires_at']) < time()) {
        $del = $conn->prepare("DELETE FROM auth_tokens WHERE id = ?");
        $del->bind_param('i', $row['token_id']);
        $del->execute();
        $del->close();
        fail('Session expired. Please log in again.', 401, 'token_expired');
    }
    if (($row['status'] ?? '') === 'Resign' || empty($row['is_active'])) {
        fail('Your account is inactive. Contact your administrator.', 403, 'account_inactive');
    }

    // Sliding expiry so an active app user is never logged out mid-use.
    $days = TOKEN_TTL_DAYS;
    $ext = $conn->prepare("UPDATE auth_tokens SET expires_at = DATE_ADD(NOW(), INTERVAL ? DAY) WHERE id = ?");
    $ext->bind_param('ii', $days, $row['token_id']);
    $ext->execute();
    $ext->close();

    $user = $row;
    return $user;
}

function require_role(array $user, string ...$roles): void {
    if (!in_array($user['role'], $roles, true)) {
        fail('You do not have permission to access this resource.', 403, 'forbidden');
    }
}

function is_admin(array $user): bool {
    return in_array($user['role'], ['admin', 'superadmin', 'hr'], true);
}

/** Admins may query any employee; everyone else is locked to their own id. */
function target_user_id(array $user): int {
    $requested = param_int('user_id');
    if ($requested && $requested !== (int)$user['id']) {
        if (!is_admin($user)) fail('You may only access your own records.', 403, 'forbidden');
        return $requested;
    }
    return (int)$user['id'];
}

// ---------------------------------------------------------------- domain helpers

/**
 * Attendance day. The shift rolls over at 06:00, so a punch at 01:00
 * still belongs to the previous calendar day. Mirrors employee/punch_*.php.
 */
function attendance_date(): string {
    $h = (int)date('H');
    $m = (int)date('i');
    return ($h < 6 || ($h === 6 && $m <= 0)) ? date('Y-m-d', strtotime('-1 day')) : date('Y-m-d');
}

function haversine_m(float $lat1, float $lon1, float $lat2, float $lon2): float {
    $R = 6371000;
    $p1 = deg2rad($lat1);
    $p2 = deg2rad($lat2);
    $dp = deg2rad($lat2 - $lat1);
    $dl = deg2rad($lon2 - $lon1);
    $a = sin($dp / 2) ** 2 + cos($p1) * cos($p2) * sin($dl / 2) ** 2;
    return $R * 2 * atan2(sqrt($a), sqrt(1 - $a));
}

/** Geofence check - only enforced for users flagged geo_restricted. */
function check_location_allowed(mysqli $conn, int $user_id, ?float $lat, ?float $lng): array {
    $u = fetch_one($conn, "SELECT geo_restricted, location FROM users WHERE id = ? LIMIT 1", 'i', [$user_id]);

    if (!$u || empty($u['geo_restricted'])) return ['allowed' => true, 'distance' => null];
    if ($lat === null || $lng === null) {
        return ['allowed' => false, 'message' => 'Location access is required to mark attendance. Please enable GPS and try again.'];
    }

    // Their own location's circle when it has coordinates and a distance, else the office geofence
    // (the same rule as att_fence_for() on the web).
    $office = $u['location'] !== null ? fetch_one($conn,
        "SELECT latitude, longitude, radius_meters, name AS office_name FROM locations
          WHERE name = ? AND latitude IS NOT NULL AND radius_meters IS NOT NULL", 's', [$u['location']]) : null;
    if (!$office) {
        $office = fetch_one($conn, "SELECT latitude, longitude, radius_meters, office_name FROM office_settings ORDER BY id LIMIT 1");
    }
    if (!$office || $office['latitude'] === null) {
        return ['allowed' => true, 'distance' => null];
    }

    $radius   = max(50, (int)($office['radius_meters'] ?? 100));
    $distance = haversine_m($lat, $lng, (float)$office['latitude'], (float)$office['longitude']);
    if ($distance > $radius) {
        return [
            'allowed'  => false,
            'distance' => round($distance),
            'message'  => 'You are ' . round($distance) . ' m away from ' . ($office['office_name'] ?? 'the office')
                        . '. Attendance is only allowed within ' . $radius . ' m.',
        ];
    }
    return ['allowed' => true, 'distance' => round($distance)];
}

/** Reverse geocode, falling back to plain coordinates when the lookup fails. */
function location_name(?float $lat, ?float $lng): string {
    if ($lat === null || $lng === null) return 'Office';
    $fallback = 'Lat: ' . number_format($lat, 4) . ', Lng: ' . number_format($lng, 4);

    $url = 'https://nominatim.openstreetmap.org/reverse?format=json&lat=' . urlencode((string)$lat)
         . '&lon=' . urlencode((string)$lng) . '&zoom=18&addressdetails=1';
    $ctx = stream_context_create([
        'http'  => ['timeout' => 3, 'user_agent' => 'AttendanceSystem/1.0'],
        'https' => ['timeout' => 3, 'user_agent' => 'AttendanceSystem/1.0'],
    ]);
    $res = @file_get_contents($url, false, $ctx);
    if ($res === false || $res === '') return $fallback;

    $data = json_decode($res, true);
    if (!$data || empty($data['address'])) return $fallback;

    $a = $data['address'];
    $parts = array_filter([$a['house_number'] ?? null, $a['road'] ?? null, $a['suburb'] ?? null, $a['city'] ?? null]);
    $name = implode(', ', array_slice(array_values($parts), 0, 3));
    return $name !== '' ? $name : $fallback;
}

/**
 * Decodes a base64 selfie (data-URI or raw) into uploads/selfies/Y/m/d.
 * Returns the stored filename - the same shape the web app writes.
 */
function save_selfie(string $base64, int $user_id, string $prefix = 'selfie'): array {
    if ($base64 === '') return ['ok' => false, 'message' => 'Selfie image is required.'];

    $data = preg_replace('#^data:image/\w+;base64,#i', '', $base64);
    $data = str_replace(' ', '+', (string)$data);
    $bin  = base64_decode($data, true);
    if ($bin === false || strlen($bin) < 100) return ['ok' => false, 'message' => 'Selfie image could not be decoded.'];
    if (strlen($bin) > 8 * 1024 * 1024) return ['ok' => false, 'message' => 'Selfie image is too large (max 8 MB).'];

    // Reject anything that is not actually an image.
    if (function_exists('getimagesizefromstring') && @getimagesizefromstring($bin) === false) {
        return ['ok' => false, 'message' => 'Selfie must be a valid JPEG or PNG image.'];
    }

    $dir = UPLOAD_BASE . '/selfies/' . date('Y/m/d');
    if (!is_dir($dir) && !mkdir($dir, 0755, true) && !is_dir($dir)) {
        return ['ok' => false, 'message' => 'Server could not create the upload folder.'];
    }

    $filename = $prefix . '_' . $user_id . '_' . date('YmdHis') . '.jpg';
    if (file_put_contents($dir . '/' . $filename, $bin) === false) {
        return ['ok' => false, 'message' => 'Server could not save the selfie image.'];
    }
    return ['ok' => true, 'filename' => $filename];
}

function base_url(): string {
    // Behind Cloudflare or any TLS-terminating proxy the request reaches PHP as
    // plain http, so the forwarded headers decide the scheme; without them the
    // app would hand the mobile client http:// photo links on an https site.
    $fwd    = strtolower((string)($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? ''));
    $secure = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
        || $fwd === 'https'
        || (string)($_SERVER['HTTP_CF_VISITOR'] ?? '') !== '' && str_contains((string)$_SERVER['HTTP_CF_VISITOR'], '"https"')
        || (int)($_SERVER['SERVER_PORT'] ?? 0) === 443;
    $scheme = $secure ? 'https' : 'http';
    $host   = $_SERVER['HTTP_HOST'] ?? 'localhost';
    // .../api/v1/index.php -> project root
    $script = str_replace('\\', '/', dirname((string)($_SERVER['SCRIPT_NAME'] ?? '')));
    $root   = preg_replace('#/api/v1.*$#', '', $script);
    return $scheme . '://' . $host . rtrim((string)$root, '/');
}

/**
 * Uploads are not web-reachable, so the app gets a signed link to files/get
 * that works without the bearer header (an <Image> tag cannot send one) and
 * expires after a day.
 */
function signed_file_url(string $path): string {
    $exp = time() + 86400;
    $sig = hash_hmac('sha256', $path . '|' . $exp, APP_KEY);
    return base_url() . '/api/v1/index.php?route=files/get&path=' . rawurlencode($path) . '&exp=' . $exp . '&sig=' . $sig;
}

/** Absolute URL for a stored selfie filename. The date folder comes from the name, as the web app files them. */
function selfie_url(?string $filename, ?string $date): ?string {
    if (!$filename) return null;
    if (preg_match('#^https?://#i', $filename)) return $filename;
    $filename = basename($filename);
    if (preg_match('/_(\d{4})(\d{2})(\d{2})\d{6}\.\w+$/', $filename, $m)) {
        $dir = "$m[1]/$m[2]/$m[3]";
    } else {
        $dir = date('Y/m/d', ($date && strtotime($date)) ? strtotime($date) : time());
    }
    return signed_file_url("selfies/$dir/$filename");
}

/**
 * URL for users.profile_photo, which holds a path relative to the project root
 * (e.g. "uploads/employee_photos/x.jpg"). A few legacy rows hold raw image
 * bytes instead of a path - those are reported as no photo rather than as a
 * broken link.
 */
function photo_url(?string $file): ?string {
    if ($file === null || trim($file) === '') return null;
    if (preg_match('#^https?://#i', $file)) return $file;

    $file = ltrim(trim($file), '/');
    // A real path is printable, short and has no control characters.
    if (strlen($file) > 255 || preg_match('/[^\x20-\x7E]/', $file)) return null;
    if (!preg_match('/\.(jpe?g|png|gif|webp)$/i', $file)) return null;
    if (strpos($file, '..') !== false) return null;

    // Stored as "uploads/profile_photos/x.jpg" (old app) or "profile_photos/x.jpg"; both live under uploads/hrms now.
    if (strpos($file, 'uploads/') === 0) $file = substr($file, 8);
    return signed_file_url($file);
}

/** Worked minutes between two TIME values, tolerating overnight shifts. */
function worked_minutes(?string $in, ?string $out): ?int {
    if (!$in || !$out) return null;
    $a = strtotime($in);
    $b = strtotime($out);
    if ($a === false || $b === false) return null;
    if ($b < $a) $b += 86400;
    return (int)round(($b - $a) / 60);
}

function hhmm(?int $minutes): ?string {
    if ($minutes === null) return null;
    return sprintf('%02d:%02d', intdiv($minutes, 60), $minutes % 60);
}

/**
 * Decodes a base64 / data-URI image the app sent and stores it beside the web
 * form's own uploads, so a ticket raised from a phone is indistinguishable
 * from one raised in a browser.
 *
 * Returns [stored, mime, size], or null when the payload is not a usable
 * image. Never throws: one bad photo must not take the ticket down with it.
 */
function store_base64_image(string $raw, string $dir): ?array {
    if (preg_match('#^data:([\w/+.-]+);base64,#i', $raw, $m)) {
        $mime = strtolower($m[1]);
        $raw  = substr($raw, strlen($m[0]));
    } else {
        $mime = '';
    }

    $bytes = base64_decode(strtr(trim($raw), ' ', '+'), true);
    if ($bytes === false || $bytes === '') return null;
    if (strlen($bytes) > MAX_UPLOAD) return null;

    // Trust the bytes over whatever type the client declared.
    $info = @getimagesizefromstring($bytes);
    if ($info === false) return null;
    $mime = $info['mime'] ?? $mime;

    $ext = [
        'image/jpeg' => 'jpg', 'image/pjpeg' => 'jpg', 'image/png' => 'png',
        'image/gif'  => 'gif', 'image/webp'  => 'webp',
    ][$mime] ?? null;
    if ($ext === null) return null;

    if (!is_dir($dir) && !@mkdir($dir, 0775, true)) return null;

    $stored = bin2hex(random_bytes(16)) . '.' . $ext;
    if (@file_put_contents($dir . '/' . $stored, $bytes) === false) return null;

    return ['stored' => $stored, 'mime' => $mime, 'size' => strlen($bytes)];
}

/** Signed, expiring link to a ticket attachment. */
function attachment_url(?string $stored): ?string {
    if (!$stored) return null;
    return signed_file_url('attachments/' . basename($stored));
}

/**
 * Normalises one attendance row for the app.
 *
 * Every field is read defensively. A column missing from the row - an older
 * schema, or a SELECT that does not list it - must degrade to null rather than
 * raise "Undefined array key", which would fail the whole request.
 */
function shape_attendance(array $r): array {
    $mins = worked_minutes($r['punch_in'] ?? null, $r['punch_out'] ?? null);
    return [
        'id'                 => isset($r['id']) ? (int)$r['id'] : null,
        'user_id'            => isset($r['user_id']) ? (int)$r['user_id'] : null,
        'date'               => $r['date'] ?? null,
        'punch_in'           => $r['punch_in'] ?? null,
        'punch_out'          => $r['punch_out'] ?? null,
        'status'             => $r['status'] ?? null,
        'worked_minutes'     => $mins,
        'worked_hours'       => hhmm($mins),
        'punch_in_location'  => $r['punch_in_location'] ?? null,
        'punch_out_location' => $r['punch_out_location'] ?? null,
        'punch_in_lat'       => isset($r['punch_in_lat']) ? (float)$r['punch_in_lat'] : null,
        'punch_in_lng'       => isset($r['punch_in_lng']) ? (float)$r['punch_in_lng'] : null,
        'punch_out_lat'      => isset($r['punch_out_lat']) ? (float)$r['punch_out_lat'] : null,
        'punch_out_lng'      => isset($r['punch_out_lng']) ? (float)$r['punch_out_lng'] : null,
        'selfie_punchin'     => selfie_url($r['selfie_punchin'] ?? null, $r['date'] ?? null),
        'selfie_punchout'    => selfie_url($r['selfie_punchout'] ?? null, $r['date'] ?? null),
        'employee_name'      => $r['employee_name'] ?? null,
        'employee_code'      => $r['employee_code'] ?? null,
        'department'         => $r['department'] ?? null,
    ];
}

/** Public-safe user object. Never includes password or face_descriptor. */
/**
 * Who does ticket work. IT is what the HRMS says it is - the IT department or
 * an IT designation - so there is no separate account to keep.
 *
 * This lives in core so every endpoint can answer it, not just the ticket
 * routes: the app asks auth/me whether to show its IT section at all.
 */
function tickets_it_designation(string $designation): bool {
    $words = ['IT', 'EDP', 'System', 'Systems', 'Network', 'Hardware', 'Software',
              'Developer', 'Programmer', 'Technical', 'Tech', 'Support', 'Helpdesk'];
    $padded = ' ' . strtolower(str_replace(['.', '-', '/'], ' ', $designation)) . ' ';
    foreach ($words as $w) {
        if (strpos($padded, ' ' . strtolower($w) . ' ') !== false) return true;
    }
    return false;
}

function tickets_can_work(array $u): bool {
    if (in_array($u['role'] ?? '', ['superadmin', 'it'], true)) return true;
    return ($u['department'] ?? '') === 'IT'
        || tickets_it_designation((string)($u['designation'] ?? ''));
}

function shape_user(array $u, bool $full = false): array {
    $out = [
        'id'            => (int)$u['id'],
        'name'          => $u['name'],
        'employee_id'   => $u['employee_id'],
        'email'         => $u['email'],
        'phone'         => $u['phone'],
        'role'          => $u['role'],
        'department'    => $u['department'],
        'company'       => $u['company'],
        'location'      => $u['location'],
        'shift_time'    => $u['shift_time'],
        'week_off'      => $u['week_off'],
        'status'        => $u['status'],
        'profile_photo' => photo_url($u['profile_photo'] ?? null),
        // Drives the app's IT section; the rules stay on the server.
        'is_it_staff'   => tickets_can_work($u),
        'is_superadmin' => ($u['role'] ?? '') === 'superadmin',
    ];
    if ($full) {
        $out += [
            'sex'              => $u['sex'] ?? null,
            'date_of_joining'  => $u['date_of_joining'] ?? null,
            'date_of_exit'     => $u['date_of_exit'] ?? null,
            'resign_date'      => $u['resign_date'] ?? null,
            'address'          => $u['address'] ?? null,
            'alternate_number' => $u['alternate_number'] ?? null,
            'geo_restricted'   => (int)($u['geo_restricted'] ?? 0) === 1,
            'password_set'     => (int)($u['password_set'] ?? 1) === 1,
        ];
    }
    return $out;
}

/** limit/offset from `page` + `per_page`, capped so a client cannot dump the table. */
function paging(int $default = 50, int $max = 200): array {
    $per  = max(1, min($max, param_int('per_page', $default)));
    $page = max(1, param_int('page', 1));
    return ['limit' => $per, 'offset' => ($page - 1) * $per, 'page' => $page, 'per_page' => $per];
}

function meta(array $p, int $total): array {
    return [
        'page'        => $p['page'],
        'per_page'    => $p['per_page'],
        'total'       => $total,
        'total_pages' => (int)ceil($total / max(1, $p['per_page'])),
    ];
}

function valid_date($d): bool {
    return is_string($d) && $d !== '' && (bool)preg_match('/^\d{4}-\d{2}-\d{2}$/', $d) && strtotime($d) !== false;
}

/** Month range from `month` (YYYY-MM), defaulting to the current month. */
function month_range(): array {
    $month = (string)param('month', date('Y-m'));
    if (!preg_match('/^\d{4}-\d{2}$/', $month)) $month = date('Y-m');
    return [$month . '-01', date('Y-m-t', strtotime($month . '-01')), $month];
}

/** Date range from `from`/`to`, falling back to the `month` range. */
function date_range(): array {
    $from = param('from');
    $to   = param('to');
    if (valid_date($from) && valid_date($to)) {
        return $from <= $to ? [$from, $to] : [$to, $from];
    }
    [$start, $end] = month_range();
    return [$start, $end];
}

// ---------------------------------------------------------------- db helpers

function fetch_all(mysqli $conn, string $sql, string $types = '', array $params = []): array {
    $stmt = $conn->prepare($sql);
    if (!$stmt) fail('Database error.', 500, 'db_error');
    if ($types !== '') $stmt->bind_param($types, ...$params);
    $stmt->execute();
    $rows = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $stmt->close();
    return $rows;
}

function fetch_one(mysqli $conn, string $sql, string $types = '', array $params = []): ?array {
    $rows = fetch_all($conn, $sql, $types, $params);
    return $rows[0] ?? null;
}

/** First column of the first row, or $default. */
function fetch_value(mysqli $conn, string $sql, string $types = '', array $params = [], $default = 0) {
    $row = fetch_one($conn, $sql, $types, $params);
    if (!$row) return $default;
    $v = reset($row);
    return $v === null ? $default : $v;
}
