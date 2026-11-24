#!/bin/sh
set -e

CERT_DIR="/etc/asterisk/keys"
mkdir -p "$CERT_DIR"

# Generar certificado TLS de Autoridad Interna para SIP-TLS (:5061) y WebRTC WSS (:8089)
if [ ! -f "$CERT_DIR/asterisk.pem" ]; then
    echo "[OpenPulse AI] Generando certificados X.509 para SIP-TLS (puerto 5061) y WSS (8089)..."
    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "$CERT_DIR/asterisk.key" \
        -out "$CERT_DIR/asterisk.crt" \
        -days 365 \
        -subj "/C=PE/ST=Lima/L=Lima/O=OpenPulse AI - PUCP TEL139/OU=Telefonia IP Segura/CN=openpulse.local" 2>/dev/null
    cat "$CERT_DIR/asterisk.crt" "$CERT_DIR/asterisk.key" > "$CERT_DIR/asterisk.pem"
    cp "$CERT_DIR/asterisk.crt" "$CERT_DIR/ca.crt"
    chown -R asterisk:asterisk "$CERT_DIR" 2>/dev/null || true
    chmod 600 "$CERT_DIR"/*
fi

# Normalizar finales de linea en scripts si se montaron desde Windows
if [ -d /opt/openpulse/scripts ]; then
    sed -i 's/\r$//' /opt/openpulse/scripts/*.sh 2>/dev/null || true
    chmod +x /opt/openpulse/scripts/*.sh 2>/dev/null || true
    if [ -f /opt/openpulse/scripts/sla_exporter.py ]; then
        python3 /opt/openpulse/scripts/sla_exporter.py >/var/log/openpulse_sla_exporter.log 2>&1 &
    fi
fi

# fail2ban: arranca con la regla de Asterisk (jail.d/asterisk.local montado desde el repositorio)
mkdir -p /var/log/asterisk /var/run/fail2ban
touch /var/log/asterisk/messages
if command -v fail2ban-client >/dev/null 2>&1; then
    fail2ban-client -x start >/var/log/openpulse_fail2ban.log 2>&1 || echo "[OpenPulse AI] fail2ban no pudo iniciar (ver /var/log/openpulse_fail2ban.log)"
fi

exec asterisk -f -vvv
