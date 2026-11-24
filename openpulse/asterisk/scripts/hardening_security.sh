#!/bin/sh
# =============================================================================
# OpenPulse AI - Endurecimiento de Asterisk y comprobaciones reales (TA3)
# Aplica nftables y muestra el estado real de SIP-TLS y fail2ban. No simula ataques:
# el ataque controlado (nmap y SIPVicious) se ejecuta desde otra maquina, solo contra
# el servidor propio y en una red aislada. Ver docs/GUIA_DESPLIEGUE_Y_DEMO_V305.md.
# =============================================================================
date '+%Y-%m-%d %H:%M:%S %z'

echo ">>> Transportes PJSIP"
asterisk -rx "pjsip show transports" 2>/dev/null || true

echo ">>> Negociacion TLS en el puerto 5061"
openssl s_client -connect 127.0.0.1:5061 </dev/null 2>/dev/null | grep -E "Protocol|Cipher|subject=" || echo "Sin respuesta TLS en 5061"

echo ">>> Contexto [default] (bloqueo de llamadas no autenticadas)"
asterisk -rx "dialplan show default" 2>/dev/null || true

echo ">>> Reglas nftables: solo puertos del servicio y limite de tasa SIP"
nft -f - <<'NFT'
table inet openpulse_security
delete table inet openpulse_security
table inet openpulse_security {
    chain input {
        type filter hook input priority 0; policy drop;
        iif lo accept
        ct state established,related accept
        ip protocol icmp accept
        udp dport 5060 limit rate over 30/second counter drop comment "Limite SIP UDP"
        tcp dport 5061 ct state new limit rate over 30/second counter drop comment "Limite SIP-TLS"
        udp dport 5060 accept
        tcp dport { 5061, 8088, 8089, 9105 } accept
        udp dport 10000-10100 accept comment "RTP/SRTP"
        counter comment "Descartado por politica"
    }
}
NFT
nft list table inet openpulse_security

echo ">>> Estado de fail2ban"
fail2ban-client status asterisk 2>/dev/null || echo "fail2ban no esta activo"
