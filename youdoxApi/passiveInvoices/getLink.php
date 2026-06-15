<?php

require '../classes/DocuMIAuth.php';
require '../classes/DocuMIService.php';
$key = $_REQUEST['key'] ?? "YxRjbIFm2DbFEmlcC5tIxw==";
$type = "PdfDocumiSimple";
try {
    $auth = new DocuMIAuth('giuseppe.grasso@gweb-ict.it', 'R5-PE@NY=w]bRvZH', 'jB5zPtXL6SHd3Wjt5ABReCJ6BKTm6sx9BbDe2GsB8h6cgKu7mmEhUYaewgGQCVnC', 'https://servizi.youdox.it/fatturazione/api/GetToken.aspx');
    $token = $auth->getToken();

    $service = new DocuMIService('https://servizi.youdox.it/fatturazione/api/InvoicesService.svc?wsdl', $token);

    $response = $service->getDownloadLink($key, $type);

    $json = json_encode($response, false);
    

} catch (Exception $e) {
    echo "Errore: " . $e->getMessage() . PHP_EOL;
}

echo $json;

?>
