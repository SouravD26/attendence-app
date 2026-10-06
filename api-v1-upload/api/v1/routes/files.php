<?php
/**
 * Serves selfies and profile photos from the private uploads/hrms folder.
 * Links come from signed_file_url(): they carry an expiry and an HMAC instead of
 * a bearer token, so the app can put them straight into an image view.
 */
declare(strict_types=1);

/** GET files/get?path=&exp=&sig= */
function files_get(mysqli $conn): void {
    $path = (string)($_GET['path'] ?? '');
    $exp  = (int)($_GET['exp'] ?? 0);
    $sig  = (string)($_GET['sig'] ?? '');

    if ($exp < time()) fail('This link has expired.', 403, 'forbidden');
    if (!hash_equals(hash_hmac('sha256', $path . '|' . $exp, APP_KEY), $sig)) fail('Invalid link.', 403, 'forbidden');
    // Ticket attachments sit in the shared uploads folder the web form writes
    // to, not under uploads/hrms, so they resolve against a different root.
    if (preg_match('#^attachments/[\w.-]+\.(jpe?g|png|gif|webp)$#i', $path)) {
        $file = UPLOAD_DIR . '/' . basename($path);
    } elseif (preg_match('#^(selfies/\d{4}/\d{2}/\d{2}|profile_photos|employee_photos)/[\w.-]+\.(jpe?g|png|gif|webp)$#i', $path)) {
        $file = UPLOAD_BASE . '/' . $path;
    } else {
        fail('Not found.', 404, 'not_found');
    }
    if (!is_file($file)) fail('Not found.', 404, 'not_found');

    header('Content-Type: ' . ((new finfo(FILEINFO_MIME_TYPE))->file($file) ?: 'application/octet-stream'));
    header('Content-Length: ' . filesize($file));
    header('Cache-Control: private, max-age=86400');
    header('X-Content-Type-Options: nosniff');
    readfile($file);
    exit;
}
