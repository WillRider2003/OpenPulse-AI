# =============================================================================
# OpenPulse AI - Script Maestro de Validacion y Evidencias para la TA3
# Ejecuta en secuencia los 4 bloques de pruebas tecnicas que completan la TA3:
#   1. Auditoria de Licencias OSI/FSF y generacion del SBOM con Syft (SPDX)
#   2. Estado real de las colas de QoS (la prueba A/B se hace con llamadas Linphone)
#   3. Pruebas de Ciberseguridad y Hacking Etico (Antes vs Despues: SIP-TLS, fail2ban, nftables)
#   4. Calculo de indicadores del SLA a partir de mediciones reales (llamadas.csv y sondeos HTTPS)
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
    docker exec $astContainer sh /opt/openpulse/scripts/qos_experimento_ab.sh estado eth0
    docker exec $astContainer sh /opt/openpulse/scripts/hardening_security.sh
} else {
    Write-Host "`n[!] No hay contenedor de Asterisk en ejecucion. Levanta la plataforma con setup.ps1 antes de las pruebas." -ForegroundColor Yellow
}

# 4. Mediciones completas del SLA (los 7 indicadores pendientes de la TA2)
Write-Host ""
$ipServ = ((Get-Content "$repoRoot\.env" | Select-String "^HOST_IP=") -replace "HOST_IP=","").Trim()
if (Test-Path "$repoRoot\mediciones\llamadas.csv") {
    python "$PSScriptRoot\2_mediciones_completas_sla.py" --llamadas "$repoRoot\mediciones\llamadas.csv" --ip $ipServ
} else {
    python "$PSScriptRoot\2_mediciones_completas_sla.py" --ip $ipServ
}

# 5. Pipeline de Edge AI Local (Whisper + Ollama Apache-2.0)
Write-Host ""
python "$PSScriptRoot\3_ia_whisper_ollama_acta.py"
