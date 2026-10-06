<?php
/**
 * Department daily-task forms.
 *
 * Four departments log their daily work in a Google Form. The app shows that
 * form natively: `forms` reads the live Google Form and describes its
 * questions, `forms/submit` posts the answers to Google on the employee's
 * behalf. Nothing is stored here - the Google sheet stays the record.
 *
 * The questions are read from Google every time (cached briefly), so editing
 * a form, or pointing a department at next month's form, needs no app update:
 * change the URL in forms_config() and that is all.
 */
declare(strict_types=1);

/** Seconds a parsed Google Form is reused before being fetched again. */
const FORMS_CACHE_TTL = 600;

/**
 * Department -> Google Form. `match` holds words looked for in the employee's
 * HRMS department name (case-insensitive, whole words).
 */
function forms_config(): array {
    return [
        'digital' => [
            'label' => 'Digital Team',
            'url'   => 'https://docs.google.com/forms/d/e/1FAIpQLSfZbYBSJz4DOTcYxGhm8ydhps2t7G_gpf5fMr1IANJKwsMlLQ/viewform',
            'match' => ['digital'],
        ],
        'events' => [
            'label' => 'San Event Team',
            'url'   => 'https://docs.google.com/forms/d/e/1FAIpQLSdcOGIo9gXyou6H9O_g-18mMh7coiYDlYOUeMaC-j0N6QfLVQ/viewform',
            'match' => ['event', 'events'],
        ],
        'reporting' => [
            'label' => 'Reporting Department',
            'url'   => 'https://docs.google.com/forms/d/e/1FAIpQLSc0rJ8LKJjmRH0hlpox71BcQHBB_kOzZ92NswzZWjX4_wkn7g/viewform',
            'match' => ['reporting', 'reporter', 'reporters'],
        ],
        'it' => [
            'label' => 'IT Department',
            'url'   => 'https://docs.google.com/forms/d/e/1FAIpQLSeCvRBdZT85eABhNQqvRzy8dfjPK_jyMgbCVB-2iSXd3KsXWA/viewform',
            'match' => ['it', 'edp', 'information technology'],
        ],
    ];
}

/** The form configured for this employee's department, or null. */
function forms_for_user(array $user): ?array {
    $dept = ' ' . strtolower(preg_replace('/[^a-z0-9]+/i', ' ', (string)($user['department'] ?? ''))) . ' ';
    if (trim($dept) === '') return null;
    foreach (forms_config() as $key => $cfg) {
        foreach ($cfg['match'] as $word) {
            if (strpos($dept, ' ' . $word . ' ') !== false) return ['key' => $key] + $cfg;
        }
    }
    return null;
}

// ---------------------------------------------------------------- Google

/** GET or POST to Google. Returns [status, body, final url]; status 0 = unreachable. */
function forms_http(string $url, ?array $post = null): array {
    $ch = curl_init($url);
    $opts = [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_MAXREDIRS      => 5,
        CURLOPT_CONNECTTIMEOUT => 8,
        CURLOPT_TIMEOUT        => 20,
        CURLOPT_USERAGENT      => 'Mozilla/5.0 (HRMS daily task form)',
        CURLOPT_HTTPHEADER     => ['Accept-Language: en'],
    ];
    if ($post !== null) {
        $opts[CURLOPT_POST]       = true;
        $opts[CURLOPT_POSTFIELDS] = forms_encode($post);
    }
    curl_setopt_array($ch, $opts);
    $body   = curl_exec($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    $final  = (string)curl_getinfo($ch, CURLINFO_EFFECTIVE_URL);
    if ($body === false) {
        error_log('API v1 forms: ' . curl_error($ch) . ' @ ' . $url);
        $status = 0;
        $body   = '';
    }
    return [$status, (string)$body, $final];
}

/** Like http_build_query, but repeats the key for list values (checkboxes). */
function forms_encode(array $pairs): string {
    $out = [];
    foreach ($pairs as $k => $v) {
        foreach ((array)$v as $one) {
            $out[] = rawurlencode((string)$k) . '=' . rawurlencode((string)$one);
        }
    }
    return implode('&', $out);
}

/**
 * Reads a Google Form's questions from the FB_PUBLIC_LOAD_DATA_ blob in its
 * page. Ends the request with 502 when Google cannot be read.
 */
function forms_schema(string $url): array {
    $cacheDir  = sys_get_temp_dir() . '/hrms_forms';
    $cacheFile = $cacheDir . '/' . sha1($url) . '.json';
    if (is_file($cacheFile) && filemtime($cacheFile) > time() - FORMS_CACHE_TTL) {
        $cached = json_decode((string)file_get_contents($cacheFile), true);
        if (is_array($cached)) return $cached;
    }

    [$status, $html, $final] = forms_http($url);
    if ($status === 0) {
        fail('Could not reach Google Forms. Please try again in a moment.', 502, 'google_unreachable');
    }
    if (stripos($final, 'accounts.google.com') !== false) {
        fail('This Google Form requires a Google sign-in, so it cannot be filled from the app.', 502, 'google_unreachable');
    }
    if ($status !== 200 || !preg_match('/FB_PUBLIC_LOAD_DATA_\s*=\s*(.*?);\s*<\/script>/s', $html, $m)) {
        error_log("API v1 forms: unreadable form ($status) $url");
        fail('The Google Form could not be read. It may be closed or moved.', 502, 'google_unreachable');
    }
    $data = json_decode($m[1], true);
    if (!is_array($data) || !isset($data[1]) || !is_array($data[1])) {
        fail('The Google Form could not be read.', 502, 'google_unreachable');
    }

    $fields = [];
    $pages  = 0;
    foreach ((array)($data[1][1] ?? []) as $item) {
        $type = (int)($item[3] ?? -1);
        if ($type === 8) { $pages++; continue; } // page break
        $field = forms_shape_item($item);
        if ($field !== null) $fields[] = $field;
    }

    $fbzx = preg_match('/name="fbzx" value="([^"]+)"/', $html, $fz) ? $fz[1] : '';
    $schema = [
        'title'        => trim((string)($data[1][8] ?? $data[3] ?? '')),
        'action'       => preg_replace('#/viewform.*$#', '/formResponse', $url),
        'fbzx'         => $fbzx,
        'page_history' => implode(',', range(0, $pages)),
        'fields'       => $fields,
    ];

    if (!is_dir($cacheDir)) @mkdir($cacheDir, 0775, true);
    @file_put_contents($cacheFile, json_encode($schema));
    return $schema;
}

/** One Google question -> the app's field description, or null to skip it. */
function forms_shape_item(array $item): ?array {
    $types = [0 => 'text', 1 => 'textarea', 2 => 'radio', 3 => 'radio', 4 => 'checkbox', 5 => 'radio', 9 => 'date', 10 => 'time'];
    $gtype = (int)($item[3] ?? -1);
    $entry = $item[4][0] ?? null;
    if (!isset($types[$gtype]) || !is_array($entry) || !isset($entry[0])) return null;

    $label = trim(preg_replace('/\s+/u', ' ', str_replace("\u{00a0}", ' ', (string)($item[1] ?? ''))));
    $type  = $types[$gtype];

    // Short answer with Google's "email" validation.
    if ($type === 'text' && isset($entry[4][0][0], $entry[4][0][1])
        && (int)$entry[4][0][0] === 2 && (int)$entry[4][0][1] === 102) {
        $type = 'email';
    }

    $options = [];
    foreach ((array)($entry[1] ?? []) as $opt) {
        $o = (string)($opt[0] ?? '');
        if ($o !== '') $options[] = $o;
    }

    // Google marks a real duration question; the department forms use plain
    // time questions for durations, so the label decides as well.
    $googleDuration = $gtype === 10 && (int)($entry[6][0] ?? 0) === 1;
    $isDuration = $gtype === 10 && ($googleDuration
        || preg_match('/\b(duration|time spent|time taken|hours spent)\b/i', $label));

    return [
        'key'             => (string)$entry[0],
        'type'            => $type,
        'label'           => $label,
        'required'        => !empty($entry[2]),
        'options'         => $options,
        'is_duration'     => (bool)$isDuration,
        'google_duration' => $googleDuration,
        'help'            => trim((string)($item[2] ?? '')),
    ];
}

/** Sensible starting values: the employee's own name and today's date. */
function forms_prefill(array $field, array $user) {
    if ($field['type'] === 'checkbox') return [];
    if ($field['type'] === 'date') return date('Y-m-d');
    if ($field['type'] === 'text'
        && preg_match('/^(name|name of (the )?(person|employee)|employee name|your name|reporter name)$/i', $field['label'])) {
        return (string)($user['name'] ?? '');
    }
    return '';
}

// ---------------------------------------------------------------- endpoints

/** GET forms */
function forms_index(mysqli $conn): void {
    require_method('GET');
    $user = auth_user($conn);
    $cfg  = forms_for_user($user);

    if ($cfg === null) {
        ok(['has_form' => false, 'department' => $user['department'] ?? null, 'form' => null]);
    }

    $schema = forms_schema($cfg['url']);
    $fields = [];
    foreach ($schema['fields'] as $f) {
        $fields[] = [
            'key'         => $f['key'],
            'type'        => $f['type'],
            'label'       => $f['label'],
            'required'    => $f['required'],
            'options'     => $f['options'],
            'is_duration' => $f['is_duration'],
            'value'       => forms_prefill($f, $user),
        ];
    }

    ok([
        'has_form'   => true,
        'department' => $user['department'] ?? null,
        'form'       => [
            'label'  => $cfg['label'],
            'title'  => $schema['title'] !== '' ? $schema['title'] : $cfg['label'],
            'fields' => $fields,
        ],
    ]);
}

/** POST forms/submit  { answers: { "<key>": value } } */
function forms_submit(mysqli $conn): void {
    require_method('POST');
    $user = auth_user($conn);
    $cfg  = forms_for_user($user);
    if ($cfg === null) {
        fail('Your department does not have a daily task form.', 404, 'no_form');
    }

    $answers = input()['answers'] ?? null;
    if (!is_array($answers)) {
        fail('Send the form answers as { "answers": { ... } }.', 422, 'validation_error');
    }

    $schema  = forms_schema($cfg['url']);
    $post    = [];
    $missing = [];
    $invalid = [];

    foreach ($schema['fields'] as $f) {
        $key = $f['key'];
        $raw = $answers[$key] ?? null;
        $entry = 'entry.' . $key;

        if ($f['type'] === 'checkbox') {
            $values = array_values(array_filter(
                array_map(fn($v) => trim((string)$v), is_array($raw) ? $raw : ($raw === null ? [] : [$raw])),
                fn($v) => $v !== ''
            ));
            if (!$values) {
                if ($f['required']) $missing[] = $f['label'];
                continue;
            }
            if (array_diff($values, $f['options'])) { $invalid[] = $f['label']; continue; }
            $post[$entry] = $values;
            continue;
        }

        $value = is_array($raw) ? '' : trim((string)($raw ?? ''));
        if ($value === '') {
            if ($f['required']) $missing[] = $f['label'];
            continue;
        }

        switch ($f['type']) {
            case 'radio':
                if (!in_array($value, $f['options'], true)) { $invalid[] = $f['label']; break; }
                $post[$entry] = $value;
                break;

            case 'date':
                if (!valid_date($value)) { $invalid[] = $f['label']; break; }
                [$y, $mo, $d] = explode('-', $value);
                $post[$entry . '_year']  = $y;
                $post[$entry . '_month'] = (string)(int)$mo;
                $post[$entry . '_day']   = (string)(int)$d;
                break;

            case 'time':
                if (!preg_match('/^(\d{1,2}):(\d{2})$/', $value, $t) || (int)$t[2] > 59
                    || (!$f['google_duration'] && (int)$t[1] > 23)) {
                    $invalid[] = $f['label'];
                    break;
                }
                $post[$entry . '_hour']   = sprintf('%02d', (int)$t[1]);
                $post[$entry . '_minute'] = $t[2];
                if ($f['google_duration']) $post[$entry . '_second'] = '00';
                break;

            case 'email':
                if (!filter_var($value, FILTER_VALIDATE_EMAIL)) { $invalid[] = $f['label']; break; }
                $post[$entry] = $value;
                break;

            default:
                $post[$entry] = mb_substr($value, 0, 5000);
        }
    }

    if ($missing) {
        fail('Please fill: ' . implode(', ', $missing), 422, 'validation_error', ['missing' => $missing]);
    }
    if ($invalid) {
        fail('Please check: ' . implode(', ', $invalid), 422, 'validation_error', ['invalid' => $invalid]);
    }

    $post['fvv']         = '1';
    $post['pageHistory'] = $schema['page_history'];
    if ($schema['fbzx'] !== '') $post['fbzx'] = $schema['fbzx'];

    [$status, $body, $final] = forms_http($schema['action'], $post);

    if ($status === 0) {
        fail('Could not reach Google Forms. Your answers were not sent - please try again.', 502, 'google_unreachable');
    }
    if (stripos($final, 'accounts.google.com') !== false) {
        fail('This Google Form requires a Google sign-in, so it cannot be filled from the app.', 502, 'google_unreachable');
    }
    if ($status !== 200) {
        error_log("API v1 forms: Google rejected submit ($status) for user " . (int)$user['id']);
        // The form may have changed since it was cached; read it fresh next time.
        @unlink(sys_get_temp_dir() . '/hrms_forms/' . sha1($cfg['url']) . '.json');
        fail('Google Forms rejected the response. The form may have changed - reopen it and try again.', 502, 'google_unreachable');
    }

    ok([
        'department' => $user['department'] ?? null,
        'form'       => $cfg['label'],
        'title'      => $schema['title'],
        'submitted_at' => date('c'),
    ], ['message' => 'Submitted to the ' . $cfg['label'] . ' Google Form.']);
}
