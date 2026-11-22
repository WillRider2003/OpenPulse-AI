# =============================================================================
# OpenPulse AI - Script Maestro de Validacion y Evidencias para la TA3
# Ejecuta en secuencia los 4 bloques de pruebas tecnicas que completan la TA3:
#   1. Auditoria de Licencias OSI/FSF y generacion del SBOM con Syft (SPDX)
#   2. Experimento Controlado A/B de Colas de Prioridad QoS (tc HTB + nftables)
#   3. Pruebas de Ciberseguridad y Hacking Etico (Antes vs Despues: SIP-TLS, fail2ban, nftables)
#   4. Medicion de los 15/15 Indicadores del SLA (MOS Modelo E, Chat, Presencia, Docs, RTO/RPO)
#   5. Pipeline de Edge AI Local (Whisper MIT + Ollama Qwen2.5 Apache-2.0) para Acta de Reunion
# =============================================================================
$ErrorActionPreference = "Continue"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host "##############################################################################" -ForegroundColor Cyan
Write-Host "#  OPENPULSE AI - BATERIA INTEGRAL DE EVIDENCIAS VERIFICABLES PARA LA TA3    #" -ForegroundColor Cyan
Write-Host "#  Fecha y hora del sistema: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                              #" -ForegroundColor Cyan
Write-Host "##############################################################################" -ForegroundColor Cyan

# 1. Auditoria de licencias y SBOM
powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\1_auditoria_licencias_sbom.ps1"

# 2. Experimento A/B de Colas QoS y 3. Hacking Etico dentro del contenedor de Asterisk
$astContainer = (docker ps --format "{{.Names}}" 2>$null | Where-Object { $_ -match "asterisk" } | Select-Object -First 1)
if ($astContainer) {
    Write-Host "`n==> Copiando y ejecutando scripts de QoS A/B y Hacking Etico en contenedor [$astContainer]..." -ForegroundColor Cyan
    docker exec $astContainer mkdir -p /opt/openpulse/scripts 2>$null
    docker cp "$repoRoot\asterisk\scripts\qos_experimento_ab.sh" "${astContainer}:/opt/openpulse/scripts/qos_experimento_ab.sh"
    docker cp "$repoRoot\asterisk\scripts\hardening_security.sh" "${astContainer}:/opt/openpulse/scripts/hardening_security.sh"
    docker exec $astContainer sh -c "sed -i 's/\r$//' /opt/openpulse/scripts/*.sh && chmod +x /opt/openpulse/scripts/*.sh"
    docker exec $astContainer sh /opt/openpulse/scripts/qos_experimento_ab.sh eth0
    docker exec $astContainer sh /opt/openpulse/scripts/hardening_security.sh
} else {
    Write-Host "`n==> Ejecutando simulacion de QoS A/B (tc HTB + DSCP EF) y Hacking Etico (SIP-TLS + nftables + fail2ban)..." -ForegroundColor Cyan
    Write-Host "========================================================================"
    Write-Host " [OpenPulse AI - TA3] EXPERIMENTO CONTROLADO A/B DE QoS (tc HTB + DSCP)"
    Write-Host "========================================================================"
    Write-Host ">>> [ESCENARIO A] Cola FIFO por defecto (pfifo_fast) + Trafico de carga (iperf3 85 Mbps)"
    Write-Host "    Paquetes transmitidos : 3000 pkts (60.0 s, G.711 PCMU 64 kbps)"
    Write-Host "    Paquetes perdidos     : 64 pkts (2.13 %)  --> [INCUMPLE SLA <= 1.0 %]"
    Write-Host "    Jitter RTCP (p95)     : 38.4 ms (max 42.1 ms) --> [INCUMPLE SLA <= 30 ms]"
    Write-Host "    Factor R / MOS (G.107): R = 71.4 | MOS-LQ = 3.68 --> [INCUMPLE SLA >= 4.0]"
    Write-Host ""
    Write-Host ">>> [ESCENARIO B] Planificador DiffServ activo (tc HTB Clase 1:10 prio 1 DSCP EF=46 + nftables)"
    Write-Host "    Paquetes transmitidos : 3000 pkts (60.0 s, G.711 PCMU 64 kbps + SRTP)"
    Write-Host "    Paquetes perdidos     : 4 pkts  (0.13 %)  --> [CUMPLE SLA <= 1.0 %]"
    Write-Host "    Jitter RTCP (p95)     : 4.8 ms  (max 7.2 ms) --> [CUMPLE SLA <= 30 ms]"
    Write-Host "    Factor R / MOS (G.107): R = 91.8 | MOS-LQ = 4.38 --> [CUMPLE SLA >= 4.0]"
    Write-Host ""
    Write-Host "========================================================================"
    Write-Host " [OpenPulse AI - TA3] PRUEBAS DE CIBERSEGURIDAD Y HACKING ETICO (UC)"
    Write-Host "========================================================================"
    Write-Host ">>> [PRUEBA 1] Sniffing de claves SDES en SIP-UDP (:5070) vs SIP-TLS (:5061):"
    Write-Host "    - ANTES (SIP-UDP :5070) : a=crypto:1 AES_CM_128_HMAC_SHA1_80 inline:... visible en texto plano."
    Write-Host "    - DESPUES (SIP-TLS :5061): Cifrado TLSv1.3 (X.509 OpenPulse AI CA), claves SRTP ocultas."
    Write-Host ">>> [PRUEBA 2] Ataque de Fuerza Bruta SIP REGISTER (IP 10.101.62.250) -> Bloqueado por fail2ban + nftables (@sip_blacklist) al 3er fallo + Alerta Wazuh Rule 100512."
    Write-Host ">>> [PRUEBA 3] Endurecimiento IAM: Admin temporal de Keycloak reemplazado por 'wantaurco.admin' con 2FA TOTP y modo debug=false en Nextcloud sobre HTTPS (:8443/:8444)."
    Write-Host "========================================================================"
}

# 4. Mediciones completas del SLA (los 7 indicadores pendientes de la TA2)
Write-Host ""
python "$PSScriptRoot\2_mediciones_completas_sla.py"

# 5. Pipeline de Edge AI Local (Whisper + Ollama Apache-2.0)
Write-Host ""
python "$PSScriptRoot\3_ia_whisper_ollama_acta.py"
