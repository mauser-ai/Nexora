<?php
declare(strict_types=1);

require_once __DIR__ . '/api/common.php';
header('Content-Type: text/html; charset=utf-8');

$token = preg_replace('/[^a-f0-9]/', '', strtolower((string)($_GET['token'] ?? '')));
$error = null;
$title = 'Condivisione file';
$files = [];
$expiresAt = null;
$expiresExpired = false;

if ($token === '') {
    $error = 'Link non valido.';
} else {
    $metaFile = $shareRoot . DIRECTORY_SEPARATOR . $token . '.json';
    if (!is_file($metaFile)) {
        $error = 'Condivisione non trovata.';
    } else {
        $metaRaw = file_get_contents($metaFile);
        $meta = is_string($metaRaw) ? json_decode($metaRaw, true) : null;
        if (!is_array($meta)) {
            $error = 'Condivisione corrotta.';
        } else {
            $expiresAt = (string)($meta['expiresAt'] ?? '');
            $expiresTs = strtotime($expiresAt ?: '') ?: 0;
            if ($expiresTs > 0 && time() > $expiresTs) {
                $expiresExpired = true;
                $error = 'Link scaduto. Questa condivisione era valida 7 giorni.';
            }
            $path = normalize_relative_path((string)($meta['path'] ?? ''));
            $full = full_path($archiveRoot, $path);
            if (!$expiresExpired && !file_exists($full)) {
                $error = 'Il contenuto condiviso non e piu disponibile.';
            } elseif (!$expiresExpired) {
                $title = basename($full);
                if (is_file($full)) {
                    $files[] = [
                        'name' => basename($full),
                        'path' => $path,
                        'size' => filesize($full) ?: 0,
                    ];
                } else {
                    $iterator = new RecursiveIteratorIterator(
                        new RecursiveDirectoryIterator($full, FilesystemIterator::SKIP_DOTS),
                        RecursiveIteratorIterator::LEAVES_ONLY
                    );
                    foreach ($iterator as $item) {
                        if (!$item->isFile()) {
                            continue;
                        }
                        $rel = relative_from_full($archiveRoot, $item->getPathname());
                        $files[] = [
                            'name' => basename($item->getPathname()),
                            'path' => $rel,
                            'size' => $item->getSize(),
                        ];
                    }
                    usort($files, fn($a, $b) => strnatcasecmp((string)$a['path'], (string)$b['path']));
                }
            }
        }
    }
}

function format_size(int $bytes): string
{
    if ($bytes < 1024) return $bytes . ' B';
    $kb = $bytes / 1024;
    if ($kb < 1024) return number_format($kb, 1) . ' KB';
    $mb = $kb / 1024;
    if ($mb < 1024) return number_format($mb, 1) . ' MB';
    $gb = $mb / 1024;
    return number_format($gb, 1) . ' GB';
}
?>
<!DOCTYPE html>
<html lang="it">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title><?= htmlspecialchars($title) ?> - Archivio</title>
  <style>
    :root {
      --brand: #034F3B;
      --bg: #f1f5f4;
      --text: #111827;
      --muted: #6b7280;
      --line: #e5e7eb;
      --white: #ffffff;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: "Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: var(--text);
      background:
        radial-gradient(circle at 8% 10%, rgba(3,79,59,0.12), transparent 32%),
        radial-gradient(circle at 90% 90%, rgba(3,79,59,0.08), transparent 40%),
        var(--bg);
    }
    .wrap {
      max-width: 980px;
      margin: 0 auto;
      padding: 40px 18px 52px;
    }
    .hero {
      margin-bottom: 18px;
    }
    .badge {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      font-size: 12px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      font-weight: 700;
      color: var(--brand);
      background: rgba(3,79,59,0.1);
      border: 1px solid rgba(3,79,59,0.22);
      border-radius: 999px;
      padding: 6px 12px;
      margin-bottom: 14px;
    }
    h1 {
      margin: 0;
      font-size: clamp(30px, 4.1vw, 46px);
      line-height: 1.08;
      letter-spacing: -0.02em;
    }
    .subtitle {
      margin: 12px 0 0;
      color: var(--muted);
      font-size: 16px;
      max-width: 680px;
      line-height: 1.45;
    }
    .card {
      background: var(--white);
      border: 1px solid var(--line);
      border-radius: 22px;
      box-shadow: 0 28px 55px rgba(15, 23, 42, 0.07);
      overflow: hidden;
    }
    .card-head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      padding: 18px 22px;
      border-bottom: 1px solid var(--line);
      background: linear-gradient(180deg, rgba(3,79,59,0.04), rgba(3,79,59,0.01));
    }
    .meta {
      color: var(--muted);
      font-size: 14px;
      font-weight: 500;
    }
    .count {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-width: 38px;
      padding: 6px 11px;
      border-radius: 999px;
      border: 1px solid rgba(3,79,59,0.28);
      color: var(--brand);
      font-size: 13px;
      font-weight: 700;
      background: rgba(3,79,59,0.07);
    }
    .list { padding: 6px 14px 12px; }
    .row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 18px;
      padding: 13px 10px;
      border-bottom: 1px dashed #edf2f7;
    }
    .row:last-child { border-bottom: none; }
    .file-main {
      min-width: 0;
      flex: 1;
    }
    .file-name {
      font-size: 15px;
      font-weight: 650;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .file-sub {
      margin-top: 4px;
      font-size: 13px;
      color: var(--muted);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      text-decoration: none;
      background: var(--brand);
      color: #fff;
      border-radius: 12px;
      padding: 9px 14px;
      font-size: 14px;
      font-weight: 700;
      border: 1px solid rgba(3,79,59,0.95);
      transition: transform .13s ease, box-shadow .13s ease;
      white-space: nowrap;
    }
    .btn:hover {
      transform: translateY(-1px);
      box-shadow: 0 8px 22px rgba(3,79,59,0.26);
    }
    .err {
      color: #991b1b;
      font-weight: 600;
      padding: 18px 22px;
      background: #fff7f7;
      border: 1px solid #fecaca;
      border-radius: 14px;
      margin-top: 14px;
    }
    .footer {
      margin-top: 14px;
      color: var(--muted);
      font-size: 12px;
      text-align: right;
    }
    @media (max-width: 720px) {
      .row { flex-direction: column; align-items: flex-start; }
      .btn { width: 100%; }
      .footer { text-align: left; }
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="hero">
      <div class="badge">Condivisione archivio</div>
      <h1><?= htmlspecialchars($title) ?></h1>
      <p class="subtitle">Il contenuto e pronto per il download. Puoi scaricare uno o piu file da questa pagina condivisa.</p>
      <?php if ($expiresAt !== null && $expiresAt !== ''): ?>
        <p class="subtitle" style="margin-top:8px;">
          Link valido fino al <strong><?= htmlspecialchars(date('d/m/Y H:i', strtotime($expiresAt) ?: time())) ?></strong>.
        </p>
      <?php endif; ?>
    </div>
    <?php if ($error !== null): ?>
      <div class="err"><?= htmlspecialchars($error) ?></div>
    <?php else: ?>
      <div class="card">
        <div class="card-head">
          <div class="meta">File disponibili per il download</div>
          <div class="count"><?= count($files) ?></div>
        </div>
        <div class="list">
          <?php foreach ($files as $file): ?>
            <div class="row">
              <div class="file-main">
                <div class="file-name"><?= htmlspecialchars((string)$file['name']) ?></div>
                <div class="file-sub"><?= htmlspecialchars((string)$file['path']) ?> • <?= htmlspecialchars(format_size((int)$file['size'])) ?></div>
              </div>
              <div>
                <a class="btn" href="/archivio/api/download.php?token=<?= urlencode($token) ?>&file=<?= urlencode((string)$file['path']) ?>">Scarica</a>
              </div>
            </div>
          <?php endforeach; ?>
        </div>
      </div>
      <div class="footer">Powered by G-Flux</div>
    <?php endif; ?>
  </div>
</body>
</html>
