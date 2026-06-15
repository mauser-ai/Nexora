<?php  
$json = file_get_contents('passiveInvoices_2024.json');  
$conv = json_decode($json, true); // Decodifica come array associativo  
$totale = 0;  
$i = 0;  

foreach ($conv as $fat) {  
    if ($fat['DichiarantePartitaIva'] == "02409450026") {  
        $totale += $fat['InfoImponibileImportoTotale'];  
        $i++;  
    }  
}  

if ($i > 0) {  
    $med = number_format($totale / $i,2);  
    $totale = number_format($totale,2);  
    echo "<h1>RAGA QUEST'ANNO SIAMO ANDATI $i VOLTE IN POSTERIA PER UNA MEDIA DI SPESA DI $med ED UN TOTALE DI $totale </h1>";  
} else {  
    echo "<h1 style='font-size:90px; margin:auto'>Nessuna spesa registrata per il DichiarantePartitaIva specificato.</h1>";  
}  
?>