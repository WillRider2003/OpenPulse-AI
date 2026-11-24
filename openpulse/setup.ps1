# =====================================================================
#  OpenPulse AI - Configuracion automatica del entorno TA3 (Windows / PowerShell)
#  Depliegue en vivo para el Laboratorio V305:
#   - Detecta la IP o la lee de .env
#   - Configura Asterisk (SIP-UDP :5070, SIP-TLS :5061, SRTP, DSCP EF=46)
#   - Instala Talk, Collabora (Nextcloud Office), OIDC y Presencia en Nextcloud
#   - Crea el grupo openpulse, los 5 usuarios y una carpeta compartida
#   - Configura Keycloak (realm openpulse, cliente OIDC nextcloud, 5 usuarios con 2FA TOTP, y admin nominal)
#   - Conecta Keycloak con Nextcloud para que aparezca el boton "Iniciar sesion con Keycloak"
#   - Aplica las colas QoS (tc HTB) y el firewall (nftables) en Asterisk
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
$kcUser     = $cfg["KC_ADMIN"];         if (-not $kcUser)     { $kcUser = "admin" }
$kcPass     = $cfg["KC_ADMIN_PASSWORD"]
$kcNomAdmin = $cfg["KC_NOMINAL_ADMIN"]; if (-not $kcNomAdmin) { $kcNomAdmin = "wantaurco.admin" }
$userPass   = $cfg["USERS_PASSWORD"]
$turnSecret = $cfg["TURN_SECRET"]
$sipPass    = $cfg["SIP_PASSWORD"]
foreach ($k in @("KC_ADMIN_PASSWORD","USERS_PASSWORD","TURN_SECRET","SIP_PASSWORD","DB_PASSWORD","NC_ADMIN_PASSWORD","GRAFANA_ADMIN_PASSWORD")) {
    if (-not $cfg[$k] -or $cfg[$k] -eq "CAMBIAR") { Write-Host "Define $k en .env (no uses el valor CAMBIAR)." -ForegroundColor Red; exit 1 }
}

if (-not $ip -or $ip -eq "PONER_TU_IP") {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -match "Wi-Fi|Ethernet" -and $_.IPAddress -notmatch "^169\.254" } | Select-Object -First 1).IPAddress
    if (-not $ip) { $ip = "127.0.0.1" }
}
Ok "HOST_IP = $ip"

# ---------------------------------------------------------------- 2. IP en Asterisk (UDP 5070 y SIP-TLS 5061) y Caddyfile
Paso "Actualizando HOST_IP en asterisk/conf/pjsip.conf y caddy/Caddyfile"
# pjsip.conf se genera desde la plantilla y no se sube a Git (contiene las claves SIP)
$pj = "asterisk\conf\pjsip.conf"
$contenido = (Get-Content "asterisk\conf\pjsip.conf.template" -Raw) -replace '__HOST_IP__', $ip -replace '__SIP_PASSWORD__', $sipPass
$contenido | Set-Content $pj -Encoding ascii -NoNewline

$caddyContent = @"
{
	auto_https disable_redirects
	local_certs
	default_sni $ip
}

https://${ip}:8443, https://localhost:8443 {
	tls internal
	reverse_proxy nextcloud:80 {
		header_up X-Forwarded-Proto https
		header_up X-Forwarded-Port 8443
	}
}

https://${ip}:8444, https://localhost:8444 {
	tls internal
	reverse_proxy keycloak:8080 {
		header_up X-Forwarded-Proto https
		header_up X-Forwarded-Port 8444
	}
}

https://${ip}:9443, https://localhost:9443 {
	tls internal
	reverse_proxy collabora:9980 {
		header_up X-Forwarded-Proto https
	}
}
"@
$caddyContent | Set-Content "caddy\Caddyfile" -Encoding ascii
Ok "pjsip.conf y caddy/Caddyfile actualizados a $ip"

# ---------------------------------------------------------------- 3. Contenedores
Paso "Levantando los contenedores de OpenPulse AI (la primera vez tarda unos minutos)"
docker compose up -d --build
docker compose restart asterisk | Out-Null

function occ   { docker compose exec -T -u www-data nextcloud php occ @args }
function kcadm { docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh @args }

Paso "Esperando a que Nextcloud termine de instalarse"
$dbPass  = $cfg["DB_PASSWORD"]
$ncAdmin = $cfg["NC_ADMIN_USER"];     if (-not $ncAdmin) { $ncAdmin = "admin" }
$ncPass  = $cfg["NC_ADMIN_PASSWORD"]

$listo = $false
for ($i = 0; $i -lt 90; $i++) {
    $st = (occ status --output=json 2>$null) -join ""
    if ($st -match '"installed":true') { $listo = $true; break }
    if ($i -eq 6 -and $st -match '"installed":false') {
        'CREATE ROLE nextcloud WITH SUPERUSER LOGIN PASSWORD ''' + $dbPass + ''';' | docker compose exec -T db psql -U openpulse -d nextcloud 2>$null | Out-Null
        'ALTER ROLE nextcloud WITH SUPERUSER LOGIN PASSWORD ''' + $dbPass + ''';'  | docker compose exec -T db psql -U openpulse -d nextcloud 2>$null | Out-Null
        occ maintenance:install --database="pgsql" --database-host="db" --database-name="nextcloud" --database-user="nextcloud" --database-pass="$dbPass" --admin-user="$ncAdmin" --admin-pass="$ncPass" 2>$null | Out-Null
    }
    Start-Sleep -Seconds 5
}
if (-not $listo) {
    Write-Host "Nextcloud no respondio a tiempo. Revisa: docker compose logs nextcloud" -ForegroundColor Red
    exit 1
}
Ok "Nextcloud 29.0.8 instalado y conectado a Valkey 8.0.1 (BSD-3-Clause)"

# ---------------------------------------------------------------- 4. Nextcloud
Paso "Instalando aplicaciones en Nextcloud (Talk, Collabora Office, OpenID Connect, Presencia)"
foreach ($app in @("spreed", "richdocuments", "user_oidc")) { occ app:install $app 2>$null }
occ app:enable user_status
occ config:system:set allow_local_remote_servers --value=true --type=boolean
occ config:system:set trusted_domains 0 --value="localhost"
occ config:system:set trusted_domains 1 --value=$ip
occ config:system:set trusted_domains 2 --value="nextcloud"
occ config:system:set trusted_domains 3 --value="caddy"
occ config:system:delete overwriteprotocol 2>$null
occ config:system:set overwrite.cli.url --value="http://${ip}:8080"
# El login OIDC por la URL HTTP de Keycloak (:8081) aun necesita debug=true en Nextcloud.
# Tarea WA_04: registrar el proveedor con https://IP:8444 y la CA de Caddy, y luego poner debug=false.
occ config:system:set debug --value=true --type=boolean

Paso "Configurando servidor STUN/TURN coturn (:3478) en Nextcloud Talk"
occ talk:stun:add "${ip}:3478" 2>$null
occ talk:turn:add turn "${ip}:3478" "udp,tcp" --secret="$turnSecret" 2>$null
Ok "coturn STUN/TURN configurado en Talk"

Paso "Creando el grupo openpulse y los 5 usuarios del equipo"
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
Ok "Usuarios wantaurco, rpretel, avallejo, lgil y lparedes listos (clave: USERS_PASSWORD de .env)"

Paso "Conectando Nextcloud con Collabora Online (edicion compartida de documentos)"
occ richdocuments:activate-config "--wopi-url=http://${ip}:9980" "--callback-url=http://${ip}:8080"
Ok "Collabora Online conectado con Nextcloud"

# ---------------------------------------------------------------- 5. Keycloak (SSO + 2FA + Admin Nominal)
Paso "Esperando a Keycloak"
$kcListo = $false
for ($i = 0; $i -lt 60; $i++) {
    kcadm config credentials --server http://localhost:8080 --realm master --user $kcUser --password $kcPass 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $kcListo = $true; break }
    Start-Sleep -Seconds 5
}
if (-not $kcListo) {
    Write-Host "No se pudo entrar a Keycloak. Revisa KC_ADMIN y KC_ADMIN_PASSWORD en .env" -ForegroundColor Red
    exit 1
}
Ok "Sesion iniciada en Keycloak"

Paso "Creando el realm openpulse y el administrador nominal '$kcNomAdmin'"
'{"realm":"openpulse","enabled":true,"displayName":"OpenPulse AI","sslRequired":"external"}' | docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh create realms -f - 2>$null
# "external": exige HTTPS salvo desde direcciones privadas (red del laboratorio)
kcadm update realms/openpulse -s sslRequired=external 2>$null
kcadm update realms/master -s sslRequired=external 2>$null

# Administrador nominal en master
$adminNominalJson = '{"username":"' + $kcNomAdmin + '","enabled":true,"emailVerified":true,"email":"a20221862@pucp.edu.pe","firstName":"Willian","lastName":"Antaurco (Admin Nominal)","requiredActions":["CONFIGURE_TOTP"]}'
$adminNominalJson | docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh create users -r master -f - 2>$null
kcadm set-password -r master --username $kcNomAdmin --new-password $kcPass 2>$null
kcadm add-roles -r master --uusername $kcNomAdmin --rolename admin 2>$null

Paso "Creando el cliente OIDC 'nextcloud' en Keycloak (compatible con HTTP :8080 y HTTPS :8443)"
$secret = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
$cliente = '{"clientId":"nextcloud","enabled":true,"protocol":"openid-connect","publicClient":false,"clientAuthenticatorType":"client-secret","secret":"' + $secret + '","standardFlowEnabled":true,"directAccessGrantsEnabled":false,"redirectUris":["http://' + $ip + ':8080/*","https://' + $ip + ':8443/*","http://localhost:8080/*","https://localhost:8443/*"],"webOrigins":["+"]}'
$existente = (kcadm get clients -r openpulse -q clientId=nextcloud --fields id) -join ""
$id = $null
if ($existente -match '"id"\s*:\s*"([^"]+)"') { $id = $matches[1] }
if ($id) {
    $cliente | docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$id" -r openpulse -f -
    Ok "Cliente OIDC nextcloud actualizado"
} else {
    $cliente | docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh create clients -r openpulse -f -
    Ok "Cliente OIDC nextcloud creado"
}

Paso "Creando los 5 usuarios en Keycloak (con doble factor TOTP obligatorio)"
foreach ($u in $usuarios) {
    $json = '{"username":"' + $u.kc + '","enabled":true,"emailVerified":true,"email":"' + $u.mail + '","firstName":"' + $u.first + '","lastName":"' + $u.last + '","requiredActions":["CONFIGURE_TOTP"]}'
    $json | docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh create users -r openpulse -f - 2>$null
    kcadm set-password -r openpulse --username $u.kc --new-password $userPass 2>$null
}

Paso "Registrando Keycloak como proveedor SSO en Nextcloud"
occ user_oidc:provider Keycloak --clientid=nextcloud "--clientsecret=$secret" "--discoveryuri=http://${ip}:8081/realms/openpulse/.well-known/openid-configuration" --mapping-uid=preferred_username --unique-uid=0
Ok "Boton 'Iniciar sesion con Keycloak' activado en Nextcloud"

# ---------------------------------------------------------------- 6. Aplicar QoS y Hardening en Asterisk
Paso "Aplicando colas de prioridad QoS (tc HTB EF=46) y Firewall (nftables) en Asterisk"
docker compose exec -T asterisk sh /opt/openpulse/scripts/qos_experimento_ab.sh htb eth0 100mbit | Out-Null
docker compose exec -T asterisk sh /opt/openpulse/scripts/hardening_security.sh | Out-Null
Ok "Colas tc HTB (Clase 1:10 EF=46) y firewall nftables (openpulse_security) activos"

# ---------------------------------------------------------------- 7. Resumen para la Demo en el Salon V305
Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host " ENTORNO OPENPULSE AI (TA3) LISTO PARA DEMO EN VIVO EN EL V305" -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host " 1. Portal Nextcloud (HTTP):   http://${ip}:8080   (ideal para Collabora en LAN)"
Write-Host " 2. Portal Nextcloud (HTTPS):  https://${ip}:8443  (vía proxy Caddy TLS)"
Write-Host " 3. Consola Keycloak (SSO):    http://${ip}:8081   o https://${ip}:8444"
Write-Host " 4. Collabora Online:          http://${ip}:9980/hosting/discovery"
Write-Host " 5. Tablero SLA Grafana OSS:   http://${ip}:3000   (admin / GRAFANA_ADMIN_PASSWORD de .env)"
Write-Host " 6. Prometheus SLA Targets:    http://${ip}:9090/targets"
Write-Host " 7. Uptime Kuma:               http://${ip}:3001"
Write-Host " 8. Asterisk (Linphone):       Dominio ${ip}:5070 (UDP) o ${ip}:5061 (TLS)"
Write-Host "    Extensiones: 1001 a 1005   Clave: SIP_PASSWORD de .env"
Write-Host ""
Write-Host " Usuarios Nextcloud: wantaurco, rpretel, avallejo, lgil, lparedes (clave: USERS_PASSWORD de .env)"
Write-Host " Usuarios Keycloak : willian.antaurco, rosell.pretel, abdon.vallejo, lucia.gil, luis.paredes"
Write-Host "=====================================================================" -ForegroundColor Green
