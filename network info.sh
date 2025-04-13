#!/bin/bash

ActivePortName=$(wdutil info | grep "Primary IPv4" | awk '{print $4}') 
transferRate=$(wdutil info | grep "Tx Rate" | awk '{print $4,$5}')
RSSI=$(wdutil info | grep "RSSI" | awk '{print $3,$4}' | head -1)
Noise=$(wdutil info | grep "Noise" | awk '{print $3,$4}')

Results="Port:     $ActivePortName
Tx Rate:        $transferRate
RSSI:    $RSSI
Noise:	$Noise"

echo "<result>$Results</result>"
