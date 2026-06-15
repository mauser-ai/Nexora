<?php

class DocuMIService {
    private $wsdl;
    private $token;

    public function __construct($wsdl, $token) {
        $this->wsdl = $wsdl;
        $this->token = $token;
    }

    private function getClient() {
        return new SoapClient($this->wsdl, array(
            'trace' => 1,
            'exceptions' => 1,
            'cache_wsdl' => WSDL_CACHE_NONE
        ));
    }

    private function call($method, $params) {
        $client = $this->getClient();
        $params['token'] = $this->token;

        try {
            $response = $client->__soapCall($method, array($params));
            return $response;
        } catch (SoapFault $fault) {
            throw new Exception("SOAP Fault: (faultcode: {$fault->faultcode}, faultstring: {$fault->faultstring})");
        }
    }

    public function allPassiveInvoices($only_unread = false) {
        $params = array(
            'only_unread' => $only_unread
        );

        return $this->call('Invoices_ListReceived', $params);
    }

    // Aggiungi altri metodi qui seguendo lo stesso schema...
}

?>
