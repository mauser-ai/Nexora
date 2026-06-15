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

    public function allActiveInvoices($only_unread = false) {
        $params = array(
            'only_unread' => $only_unread
        );

        return $this->call('Invoices_ListSent', $params);
    }

    public function getStatistics($only_unread = false) {
        $params = array(
           
        );

        return $this->call('Account_GetStatistics', $params);
    }

     public function getDownloadLink($key, $type) {
        $params = array(
            'invoice_key' => $key,
            'type' => $type,
        );

        return $this->call('Invoices_GetDownloadLink', $params);
    }

    public function getAccountInfo() {
        $params = array(
            
        );

        return $this->call('GetUserData', $params);
    }

    // Aggiungi altri metodi qui seguendo lo stesso schema...
}

?>
