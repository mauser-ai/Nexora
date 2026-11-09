<?php
// Apri nel browser per vedere la versione PHP e l'ultimo errore
// Elimina dopo il debug.
echo '<pre>';
echo 'PHP version: ' . PHP_VERSION . "\n";
echo 'Extensions: openssl=' . (extension_loaded('openssl') ? 'yes' : 'NO')
   . ' curl=' . (extension_loaded('curl') ? 'yes' : 'NO')
   . ' pdo_mysql=' . (extension_loaded('pdo_mysql') ? 'yes' : 'NO') . "\n";

// Prova a caricare bootstrap e cattura errori
ini_set('display_errors', 1);
error_reporting(E_ALL);
try {
    require_once __DIR__ . '/bootstrap.php';
    echo "bootstrap.php: OK\n";
} catch (Throwable $e) {
    echo "bootstrap.php ERROR: " . $e->getMessage() . " in " . $e->getFile() . ":" . $e->getLine() . "\n";
}
echo '</pre>';
