<?php

require '../classes/DocuMIAuth.php';
require '../classes/DocuMIService.php';

try {
    $auth = new DocuMIAuth('giuseppe.grasso@gweb-ict.it', 'R5-PE@NY=w]bRvZH', 'jB5zPtXL6SHd3Wjt5ABReCJ6BKTm6sx9BbDe2GsB8h6cgKu7mmEhUYaewgGQCVnC', 'https://servizi.youdox.it/fatturazione/api/GetToken.aspx');
    $token = $auth->getToken();

    $service = new DocuMIService('https://servizi.youdox.it/fatturazione/api/AccountService.svc?wsdl', $token);

    $response = $service->getAccountInfo();

    $json = json_encode($response, false);
    $array = json_decode($json, true);
    $currentYear = date('Y');
    $filteredInvoices = [];

    echo $json;

} catch (Exception $e) {
    echo "Errore: " . $e->getMessage() . PHP_EOL;
}

?>
