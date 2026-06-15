<?php
// Leggi il file JSON
$jsonData = file_get_contents('passiveInvoices_2024.json');

// Decodifica il JSON in un array associativo
$invoices = json_decode($jsonData, true);

// Inizializza l'array per conservare le aziende uniche
$uniqueCompanies = [];

// Scorri tutte le fatture
foreach ($invoices as $invoice) {
    $piva = $invoice['DichiarantePartitaIva'];
    $ragioneSociale = $invoice['DichiaranteDenominazione'];

    // Controlla se la partita IVA è già stata inserita
    if (!isset($uniqueCompanies[$piva])) {
        // Aggiungi l'azienda solo se la P.IVA non è già presente
        $uniqueCompanies[$piva] = $ragioneSociale;
    }
}

// Risultato finale
print_r($uniqueCompanies);
