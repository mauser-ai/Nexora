<?php

require '../classes/DocuMIAuth.php';
require '../classes/DocuMIService.php';

try {
    $auth = new DocuMIAuth('giuseppe.grasso@gweb-ict.it', 'R5-PE@NY=w]bRvZH', 'jB5zPtXL6SHd3Wjt5ABReCJ6BKTm6sx9BbDe2GsB8h6cgKu7mmEhUYaewgGQCVnC', 'https://servizi.youdox.it/fatturazione/api/GetToken.aspx');
    $token = $auth->getToken();

    $service = new DocuMIService('https://servizi.youdox.it/fatturazione/api/InvoicesService.svc?wsdl', $token);

    $response = $service->allActiveInvoices();

    $json = json_encode($response, false);
    $array = json_decode($json, true);
    $currentYear = date('Y');
    $filteredInvoices = [];

    foreach ($array as $data) {
        foreach ($data as $invoice) {
            foreach ($invoice as $single_invoice) {
                $invoiceDate = strtotime($single_invoice['FatturaData']);
                $year = date('Y', $invoiceDate);

                if ($year == $currentYear) {
                    $filteredInvoices[] = $single_invoice;
                }
            }
        }
    }

    // Costruisci il percorso del file
    $filePath = "data/activeInvoices/activeInvoices_$currentYear.json";
    
    // Codifica le fatture filtrate in JSON
    $filteredInvoicesJson = json_encode($filteredInvoices);
    
    // Salva il JSON nel file
    if (!file_exists(dirname($filePath))) {
        mkdir(dirname($filePath), 0777, true);
    }
    file_put_contents($filePath, $filteredInvoicesJson);

    echo "Fatture attive salvate in $filePath";

} catch (Exception $e) {
    echo "Errore: " . $e->getMessage() . PHP_EOL;
}

?>
