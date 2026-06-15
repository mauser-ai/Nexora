<?php

require 'DocuMIAuth.php';
require 'DocuMIService.php';

try {
    $auth = new DocuMIAuth('giuseppe.grasso@gweb-ict.it', 'R5-PE@NY=w]bRvZH', 'jB5zPtXL6SHd3Wjt5ABReCJ6BKTm6sx9BbDe2GsB8h6cgKu7mmEhUYaewgGQCVnC', 'https://servizi.youdox.it/fatturazione/api/GetToken.aspx');
    $token = $auth->getToken();

    $service = new DocuMIService('https://servizi.youdox.it/fatturazione/api/InvoicesService.svc?wsdl', $token);

    $response = $service->allPassiveInvoices();

    $json = json_encode($response, false);
    $array = json_decode($json, true);
    $tot = 0;

    foreach ($array as $data) {
        foreach ($data as $invoice) {
            foreach ($invoice as $single_invoice) {
                $data = strtotime($single_invoice['FatturaData']);
                $month = date('m', $data);
                $year = date('Y', $data);

                if($month == date('m') && $year == date('Y')){

$tot += $single_invoice['InfoImponibileImportoTotale'];
                }
                    
                

                

            }


        }

    }


    echo $tot;


} catch (Exception $e) {
    echo "Errore: " . $e->getMessage() . PHP_EOL;
}

?>