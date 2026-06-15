<?php
// Credenziali
$client_id = "jB5zPtXL6SHd3Wjt5ABReCJ6BKTm6sx9BbDe2GsB8h6cgKu7mmEhUYaewgGQCVnC";
$username = "giuseppe.grasso@gweb-ict.it";
$password = "R5-PE@NY=w]bRvZH";

// Endpoint per ottenere il token
$token_url = "https://servizi.youdox.it/fatturazione/api/GetToken.aspx";

// Funzione per ottenere il token
function get_token($url, $username, $password, $client_id) {
    $params = array(
        'username' => $username,
        'password' => $password,
        'client_id' => $client_id
    );

    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($params));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);

    $response = curl_exec($ch);
    curl_close($ch);

    return json_decode($response, true);
}

// Ottenere il token
$token_response = get_token($token_url, $username, $password, $client_id);
if (isset($token_response['access_token'])) {
    $access_token = $token_response['access_token'];

    // Endpoint per il servizio InvoicesService
    $service_url = "https://servizi.youdox.it/fatturazione/api/InvoicesService.svc";

    // Funzione per chiamare il metodo ListReceived
    function list_received_invoices($url, $token, $only_unread) {
        $client = new SoapClient("$url?wsdl", array('trace' => 1));

        $params = array(
            'only_unread' => $only_unread,
            'token' => $token
        );

        try {
            $response = $client->ListReceived($params);
            return $response;
        } catch (SoapFault $fault) {
            echo "Error: " . $fault->faultcode . ", string: " . $fault->faultstring;
        }
    }

    // Ottenere l'elenco delle fatture ricevute
    $only_unread = false; // o false a seconda delle necessità
    $invoices = list_received_invoices($service_url, $access_token, $only_unread);

    echo "<pre>";
    print_r($invoices);
    echo "</pre>";
} else {
    echo "Errore: " . $token_response['error_message'];
}
?>
