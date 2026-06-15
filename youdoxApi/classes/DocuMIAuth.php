<?php

class DocuMIAuth {
    private $username;
    private $password;
    private $client_id;
    private $token_endpoint;

    public function __construct($username, $password, $client_id, $token_endpoint) {
        $this->username = $username;
        $this->password = $password;
        $this->client_id = $client_id;
        $this->token_endpoint = $token_endpoint;
    }

    public function getToken() {
        $credentials = array(
            'username' => $this->username,
            'password' => $this->password,
            'client_id' => $this->client_id
        );

        $ch = curl_init($this->token_endpoint);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, array('Content-Type: application/x-www-form-urlencoded'));
        curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($credentials));

        $response = curl_exec($ch);

        if ($response === false) {
            $error = curl_error($ch);
            curl_close($ch);
            throw new Exception('Errore nella richiesta cURL: ' . $error);
        }

        curl_close($ch);

        $responseData = json_decode($response, true);

        if (isset($responseData['access_token'])) {
            return $responseData['access_token'];
        } else {
            $error = isset($responseData['error']) ? $responseData['error'] : 'Unknown error';
            $errorMessage = isset($responseData['error_message']) ? $responseData['error_message'] : 'No error message';
            throw new Exception('Error: ' . $error . ' - ' . $errorMessage);
        }
    }
}
?>
