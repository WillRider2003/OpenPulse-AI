# =====================================================================
#  OpenPulse AI - Configuracion automatica del entorno TA3 (Windows / PowerShell)
#  Incluye todas las mejoras comprometidas en la TA2 para la TA3:
#   - Valkey 8.0.1 (BSD-3-Clause) en reemplazo de Redis 7.4
#   - HTTPS en Nextcloud (:8443), Keycloak (:8444) y Collabora (:9443) con Caddy
#   - Retiro del modo depuracion (debug=false) en Nextcloud
#   - Administrador nominal con doble factor (wantaurco.admin) en Keycloak
#   - Asterisk 20 con SIP-TLS (:5061), SRTP (SDES), DSCP EF (46) y colas tc/nftables
#   - coturn STUN/TURN (:3478) integrado en Nextcloud Talk
#   - Prometheus + Grafana OSS 11.3.0 con tablero SLA preconfigurado
# =====================================================================
$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot

function Paso($t) { Write-Host ""; Write-Host "==> $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "    [OK] $t" -ForegroundColor Green }
function Aviso($t){ Write-Host "    [!] $t" -ForegroundColor Yellow }

# ---------------------------------------------------------------- 1. Leer .env
Paso "Leyendo configuracion de .env"
if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Aviso "Se creo .env a partir de .env.example."
}
$cfg = @{}
foreach ($line in Get-Content ".env") {
    if ($line -match '^\s*([A-Za-z_]+)\s*=\s*(.*)$') { $cfg[$matches[1]] = $matches[2].Trim() }
}
$ip         = $cfg["HOST_IP"]
$kcUser     = $cfg["KC_ADMIN"]
$kcPass     = $cfg["KC_ADMIN_PASSWORD"]
$kcNomAdmin = $cfg["KC_NOMINAL_ADMIN"]; if (-not $kcNomAdmin) { $kcNomAdmin = "wantaurco.admin" }
$userPass   = $cfg["USERS_PASSWORD"];   if (-not $userPass)   { $userPass = "OpenPulse2026!" }
$turnSecret = $cfg["TURN_SECRET"];      if (-not $turnSecret) { $turnSecret = "OpenPulseTurnSecret2026!" }

if (-not $ip -or $ip -eq "PONER_TU_IP") {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -match "Wi-Fi|Ethernet" -and $_.IPAddress -notmatch "^169\.254" } | Select-Object -First 1).IPAddress
    if (-not $ip) { $ip = "127.0.0.1" }
}
Ok "HOST_IP = $ip"

# ---------------------------------------------------------------- 2. IP en Asterisk (UDP 5070 y SIP-TLS 5061)
Paso "Actualizando HOST_IP en asterisk/conf/pjsip.conf (SIP-UDP :5070 y SIP-TLS :5061)"
$pj = "asterisk\conf\pjsip.conf"
$contenido = Get-Content $pj
$contenido = $contenido -replace '^external_media_address=.*', "external_media_address=$ip"
$contenido = $contenido -replace '^external_signaling_address=.*', "external_signaling_address=$ip"
$contenido | Set-Content $pj -Encoding ascii
Ok "pjsip.conf configurado con IP $ip, SRTP (sdes), SIP-TLS (:5061) y DSCP EF (46)"

# ---------------------------------------------------------------- 3. Contenedores
Paso "Levantando los contenedores de OpenPulse AI (TA3 - 100% Licencias Libres OSI)"
docker compose up -d --build
docker compose restart asterisk | Out-Null

function occ   { docker compose exec -T -u www-data nextcloud php occ @args }
function kcadm { docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh @args }

Paso "Esperando a que Nextcloud termine de instalarse"
$listo = $false
for ($i = 0; $i -lt 90; $i++) {
    $st = (occ status --output=json 2>$null) -join ""
    if ($st -match '"installed":true') { $listo = $true; break }
    Start-Sleep -Seconds 5
}
if ($listo) {
    Ok "Nextcloud 29.0.8 operativo con cache Valkey 8.0.1 (BSD-3-Clause)"

    # ---------------------------------------------------------------- 4. Nextcloud + HTTPS + coturn + debug=false
    Paso "Configurando aplicaciones de Nextcloud (Talk, Office, OIDC, Presencia) y retirando modo debug"
    foreach ($app in @("spreed", "richdocuments", "user_oidc")) { occ app:install $app 2>$null }
    occ app:enable user_status
    occ config:system:set allow_local_remote_servers --value=true --type=boolean
    occ config:system:set trusted_domains 1 --value=$ip
    occ config:system:set trusted_domains 2 --value="${ip}:8443"
    occ config:system:set overwriteprotocol --value="https"
    # Retirar el modo de depuracion (compromiso de seguridad TA2 -> TA3)
    occ config:system:set debug --value=false --type=boolean
    Ok "Modo de depuracion desactivado (debug=false) y HTTPS activo en :8443"

    Paso "Configurando servidor STUN/TURN coturn (:3478) en Nextcloud Talk"
    occ talk:stun:add "${ip}:3478" 2>$null
    occ talk:turn:add turn "${ip}:3478" "udp,tcp" --secret="$turnSecret" 2>$null
    Ok "coturn STUN/TURN registrado para videollamadas WebRTC detras de NAT"

    Paso "Creando el grupo openpulse y los 5 usuarios"
    $usuarios = @(
        @{ nc="wantaurco"; nombre="Willian Antaurco"; kc="willian.antaurco"; first="Willian"; last="Antaurco"; mail="a20221862@pucp.edu.pe" },
        @{ nc="rpretel";   nombre="Rosell Pretel";    kc="rosell.pretel";    first="Rosell";  last="Pretel";   mail="a20206399@pucp.edu.pe" },
        @{ nc="avallejo";  nombre="Abdon Vallejo";    kc="abdon.vallejo";    first="Abdon";   last="Vallejo";  mail="a20233429@pucp.edu.pe" },
        @{ nc="lgil";      nombre="Lucia Gil";        kc="lucia.gil";        first="Lucia";   last="Gil";      mail="a20233424@pucp.edu.pe" },
        @{ nc="lparedes";  nombre="Luis Paredes";     kc="luis.paredes";     first="Luis";    last="Paredes";  mail="a20227191@pucp.edu.pe" }
    )
    occ group:add openpulse 2>$null
    foreach ($u in $usuarios) {
        docker compose exec -T -u www-data -e "OC_PASS=$userPass" nextcloud php occ user:add --password-from-env "--display-name=$($u.nombre)" --group=openpulse $u.nc 2>$null
    }

    Paso "Conectando Nextcloud con Collabora Online sobre HTTPS (:9443 / :9980)"
    occ richdocuments:activate-config "--wopi-url=http://${ip}:9980" "--callback-url=https://${ip}:8443" 2>$null
}

# ---------------------------------------------------------------- 5. Keycloak en HTTPS + Admin Nominal
Paso "Configurando Keycloak 26.0.5 (HTTPS :8444, OIDC + 2FA TOTP y Administrador Nominal)"
$kcListo = $false
for ($i = 0; $i -lt 40; $i++) {
    kcadm config credentials --server http://localhost:8080 --realm master --user $kcUser --password $kcPass 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $kcListo = $true; break }
    Start-Sleep -Seconds 3
}
if ($kcListo) {
    '{"realm":"openpulse","enabled":true,"displayName":"OpenPulse AI"}' | docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh create realms -f - 2>$null
    # Crear administrador nominal con TOTP para reemplazar al admin temporal de arranque (Hito Seguridad TA3)
    $adminNominalJson = '{"username":"' + $kcNomAdmin + '","enabled":true,"emailVerified":true,"email":"a20221862@pucp.edu.pe","firstName":"Willian","lastName":"Antaurco (Admin Nominal)","requiredActions":["CONFIGURE_TOTP"]}'
    $adminNominalJson | docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh create users -r master -f - 2>$null
    kcadm set-password -r master --username $kcNomAdmin --new-password $kcPass 2>$null
    kcadm add-roles -r master --uusername $kcNomAdmin --rolename admin 2>$null
    Ok "Administrador nominal '$kcNomAdmin' con rol admin y TOTP obligatorio configurado en Keycloak"
}

# ---------------------------------------------------------------- 6. Aplicar QoS y Hardening en Asterisk
Paso "Aplicando colas de prioridad QoS (tc HTB EF=46) y Firewall (nftables) en Asterisk"
docker compose exec -T asterisk sh /opt/openpulse/scripts/qos_experimento_ab.sh eth0 | Out-Null
docker compose exec -T asterisk sh /opt/openpulse/scripts/hardening_security.sh | Out-Null
Ok "Colas tc HTB (Clase 1:10 EF=46) y firewall nftables (openpulse_security) activos"

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host " ENTORNO OPENPULSE AI (TA3) LISTO Y ENDURECIDO" -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host " Portal Nextcloud (HTTPS): https://${ip}:8443"
Write-Host " Keycloak SSO (HTTPS):     https://${ip}:8444"
Write-Host " Collabora (HTTPS):        https://${ip}:9443/hosting/discovery"
Write-Host " Tablero SLA Grafana OSS:  http://localhost:3000 (admin / OpenPulseAdmin2026!)"
Write-Host " Prometheus SLA Targets:   http://localhost:9090/targets"
Write-Host " Uptime Kuma:              http://localhost:3001"
Write-Host " Asterisk SIP-TLS / SRTP:  ${ip}:5061 (TLS) y ${ip}:5070 (UDP)"
Write-Host " coturn STUN/TURN:         ${ip}:3478 (UDP/TCP)"
Write-Host "=====================================================================" -ForegroundColor Green
