<?php
/**
 * Mobile API v1 - front controller.
 *
 * Every endpoint is reachable two ways, so the app works with or without
 * mod_rewrite:
 *   GET  /attendence/api/v1/attendance/today
 *   GET  /attendence/api/v1/index.php?route=attendance/today
 */
declare(strict_types=1);

require_once __DIR__ . '/core.php';

// ---------------------------------------------------------------- CORS

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
header('Access-Control-Max-Age: 86400');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

// ------------------------------------------------------- error reporting

/**
 * True when the caller has proved they may see error details.
 *
 * Define API_DEBUG_KEY in includes/config.php as a long random string, then
 * pass it as ?debug=<key> or an X-Debug-Key header. Undefined or empty (the
 * default) means the API never reveals internals, exactly as before.
 */
function debug_allowed(): bool {
    if (!defined('API_DEBUG_KEY') || (string)API_DEBUG_KEY === '') return false;
    $given = (string)($_GET['debug'] ?? $_SERVER['HTTP_X_DEBUG_KEY'] ?? '');
    return $given !== '' && hash_equals((string)API_DEBUG_KEY, $given);
}

function error_label(int $no): string {
    $names = [
        E_ERROR => 'E_ERROR', E_WARNING => 'E_WARNING', E_PARSE => 'E_PARSE',
        E_NOTICE => 'E_NOTICE', E_CORE_ERROR => 'E_CORE_ERROR',
        E_COMPILE_ERROR => 'E_COMPILE_ERROR', E_USER_ERROR => 'E_USER_ERROR',
        E_USER_WARNING => 'E_USER_WARNING', E_USER_NOTICE => 'E_USER_NOTICE',
        E_RECOVERABLE_ERROR => 'E_RECOVERABLE_ERROR',
        E_DEPRECATED => 'E_DEPRECATED', E_USER_DEPRECATED => 'E_USER_DEPRECATED',
    ];
    return $names[$no] ?? 'E_UNKNOWN(' . $no . ')';
}

/** Log the failure, and disclose it only to a caller holding the debug key. */
function report_failure(string $type, string $message, string $file, int $line, array $trace = []): void {
    error_log(sprintf('API v1 %s: %s @ %s:%d', $type, $message, $file, $line));

    $extra = [];
    if (debug_allowed()) {
        $extra['debug'] = [
            'type'    => $type,
            'message' => $message,
            'file'    => $file,
            'line'    => $line,
            'php'     => PHP_VERSION,
        ];
        if ($trace) $extra['debug']['trace'] = array_slice($trace, 0, 8);
    }
    fail('Internal server error.', 500, 'server_error', $extra);
}

// Any uncaught problem still has to come back as JSON.
set_exception_handler(function (Throwable $e): void {
    report_failure(
        get_class($e),
        $e->getMessage(),
        $e->getFile(),
        $e->getLine(),
        explode("\n", $e->getTraceAsString())
    );
});

set_error_handler(function (int $no, string $str, string $file = '', int $line = 0): bool {
    if (!(error_reporting() & $no)) return false;

    // Notices, warnings and deprecations are logged, not fatal. Promoting them
    // meant a single "Undefined array key" took a whole endpoint down with a
    // blank 500 - and which notices PHP raises differs between versions, so
    // code that ran locally could die in production for no visible reason.
    if (!($no & (E_USER_ERROR | E_RECOVERABLE_ERROR))) {
        error_log(sprintf('API v1 %s: %s @ %s:%d', error_label($no), $str, $file, $line));
        return true;
    }
    throw new ErrorException($str, 0, $no, $file, $line);
});

// A parse or fatal error never reaches the handlers above, and would otherwise
// return an empty 500 that tells the client nothing at all.
register_shutdown_function(function (): void {
    $last = error_get_last();
    if (!$last) return;
    if (!($last['type'] & (E_ERROR | E_PARSE | E_CORE_ERROR | E_COMPILE_ERROR))) return;

    report_failure(
        error_label($last['type']),
        $last['message'],
        (string)($last['file'] ?? ''),
        (int)($last['line'] ?? 0)
    );
});

// ---------------------------------------------------------------- route

function current_route(): string {
    $route = (string)($_GET['route'] ?? '');
    if ($route === '') {
        $path = parse_url((string)($_SERVER['REQUEST_URI'] ?? ''), PHP_URL_PATH) ?: '';
        // Strip everything up to and including /api/v1
        if (preg_match('#/api/v1/?(.*)$#i', $path, $m)) $route = $m[1];
    }
    $route = trim(preg_replace('#/+#', '/', $route), '/');
    if (stripos($route, 'index.php') === 0) $route = trim(substr($route, 9), '/');
    return strtolower($route);
}

$route   = current_route();
$segments = $route === '' ? [] : explode('/', $route);

// A trailing numeric segment is an id: attendance/history/12 -> id = 12
if (count($segments) > 1 && ctype_digit(end($segments))) {
    $_GET['id'] = (int)array_pop($segments);
    $route = implode('/', $segments);
}

if ($route === '' || $route === 'index.php') {
    require __DIR__ . '/routes/meta.php';
    route_index();
}

// group/action -> routes/<group>.php, handler <group>_<action>()
$group  = $segments[0] ?? '';
$action = $segments[1] ?? 'index';

$allowed = ['auth', 'profile', 'attendance', 'leave', 'tickets', 'employees', 'admin', 'master', 'meta', 'files', 'forms'];
if (!in_array($group, $allowed, true)) {
    fail('Unknown endpoint: ' . $route, 404, 'not_found');
}

$file = __DIR__ . '/routes/' . $group . '.php';
if (!is_file($file)) fail('Unknown endpoint: ' . $route, 404, 'not_found');
require $file;

$handler = $group . '_' . str_replace('-', '_', $action);
if (!function_exists($handler)) {
    fail('Unknown endpoint: ' . $route, 404, 'not_found');
}

$handler($conn);

// A handler must always respond; reaching here means it did not.
fail('Endpoint produced no response.', 500, 'server_error');
