# =====================================================================
#  OpenPulse AI - Configuracion automatica del entorno (Windows / PowerShell)
#  Uso:  1) Editar .env (HOST_IP y contrasenas)
#        2) En PowerShell, dentro de la carpeta openpulse:
#             powershell -ExecutionPolicy Bypass -File .\setup.ps1
#  El script se puede ejecutar varias veces: si algo ya existe, lo deja igual.
# =====================================================================
$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot

function Paso($t) { Write-Host ""; Write-Host "==> $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "    $t" -ForegroundColor Green }
function Aviso($t){ Write-Host "    $t" -ForegroundColor Yellow }

# ---------------------------------------------------------------- 1. Leer .env
Paso "Leyendo configuracion de .env"
if (-not (Test-Path ".env")) {
    Write-Host "No existe el archivo .env. Copia .env.example como .env y completalo." -ForegroundColor Red
    exit 1
}
$cfg = @{}
foreach ($line in Get-Content ".env") {
    if ($line -match '^\s*([A-Za-z_]+)\s*=\s*(.*)$') { $cfg[$matches[1]] = $matches[2].Trim() }
}
$ip        = $cfg["HOST_IP"]
$kcUser    = $cfg["KC_ADMIN"]
$kcPass    = $cfg["KC_ADMIN_PASSWORD"]
$userPass  = $cfg["USERS_PASSWORD"]
if (-not $userPass) { $userPass = "OpenPulse2026!" }
if (-not $ip -or $ip -eq "PONER_TU_IP") {
    Write-Host "Define HOST_IP en .env (la IPv4 de tu Wi-Fi o Ethernet, ver con ipconfig)." -ForegroundColor Red
    exit 1
}
Ok "HOST_IP = $ip"

# ---------------------------------------------------------------- 2. IP en Asterisk
Paso "Actualizando la IP en asterisk/conf/pjsip.conf"
$pj = "asterisk\conf\pjsip.conf"
$contenido = Get-Content $pj
$contenido = $contenido -replace '^external_media_address=.*', "external_media_address=$ip"
$contenido = $contenido -replace '^external_signaling_address=.*', "external_signaling_address=$ip"
$contenido | Set-Content $pj -Encoding ascii
Ok "pjsip.conf apunta a $ip (puerto SIP 5070)"

# ---------------------------------------------------------------- 3. Contenedores
Paso "Levantando los contenedores (la primera vez tarda varios minutos)"
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
if (-not $listo) { Write-Host "Nextcloud no respondio a tiempo. Revisa: docker compose logs nextcloud" -ForegroundColor Red; exit 1 }
Ok "Nextcloud instalado"

# ---------------------------------------------------------------- 4. Nextcloud
Paso "Instalando aplicaciones de Nextcloud (Talk, Office, OpenID Connect)"
foreach ($app in @("spreed", "richdocuments", "user_oidc")) { occ app:install $app }
occ app:enable user_status
occ config:system:set allow_local_remote_servers --value=true --type=boolean
occ config:system:set trusted_domains 1 --value=$ip

Paso "Creando el grupo openpulse y los usuarios locales"
$usuarios = @(
    @{ nc="wantaurco"; nombre="Willian Antaurco"; kc="willian.antaurco"; first="Willian"; last="Antaurco"; mail="a20221862@pucp.edu.pe" },
    @{ nc="rpretel";   nombre="Rosell Pretel";    kc="rosell.pretel";    first="Rosell";  last="Pretel";   mail="a20206399@pucp.edu.pe" },
    @{ nc="avallejo";  nombre="Abdon Vallejo";    kc="abdon.vallejo";    first="Abdon";   last="Vallejo";  mail="a20233429@pucp.edu.pe" },
    @{ nc="lgil";      nombre="Lucia Gil";        kc="lucia.gil";        first="Lucia";   last="Gil";      mail="a20233424@pucp.edu.pe" },
    @{ nc="lparedes";  nombre="Luis Paredes";     kc="luis.paredes";     first="Luis";    last="Paredes";  mail="a20227191@pucp.edu.pe" }
)
occ group:add openpulse
foreach ($u in $usuarios) {
    docker compose exec -T -u www-data -e "OC_PASS=$userPass" nextcloud php occ user:add --password-from-env "--display-name=$($u.nombre)" --group=openpulse $u.nc
}

Paso "Conectando Nextcloud con Collabora"
occ richdocuments:activate-config "--wopi-url=http://${ip}:9980" "--callback-url=http://${ip}:8080"

# ---------------------------------------------------------------- 5. Keycloak
Paso "Esperando a Keycloak"
$listo = $false
for ($i = 0; $i -lt 60; $i++) {
    kcadm config credentials --server http://localhost:8080 --realm master --user $kcUser --password $kcPass 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $listo = $true; break }
    Start-Sleep -Seconds 5
}
if (-not $listo) { Write-Host "No se pudo entrar a Keycloak. Revisa KC_ADMIN y KC_ADMIN_PASSWORD en .env" -ForegroundColor Red; exit 1 }
Ok "Sesion iniciada en Keycloak"

Paso "Creando el realm openpulse"
'{"realm":"openpulse","enabled":true,"displayName":"OpenPulse AI"}' | docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh create realms -f -

Paso "Creando el cliente nextcloud"
$secret = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
$cliente = '{"clientId":"nextcloud","enabled":true,"protocol":"openid-connect","publicClient":false,"clientAuthenticatorType":"client-secret","secret":"' + $secret + '","standardFlowEnabled":true,"directAccessGrantsEnabled":false,"redirectUris":["http://' + $ip + ':8080/*","http://localhost:8080/*"],"webOrigins":["+"]}'
$existente = (kcadm get clients -r openpulse -q clientId=nextcloud --fields id) -join ""
$id = $null
if ($existente -match '"id"\s*:\s*"([^"]+)"') { $id = $matches[1] }
if ($id) {
    $cliente | docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$id" -r openpulse -f -
    Ok "Cliente nextcloud actualizado (secreto nuevo)"
} else {
    $cliente | docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh create clients -r openpulse -f -
    Ok "Cliente nextcloud creado"
}

Paso "Creando usuarios en Keycloak (con doble factor obligatorio)"
foreach ($u in $usuarios) {
    $json = '{"username":"' + $u.kc + '","enabled":true,"emailVerified":true,"email":"' + $u.mail + '","firstName":"' + $u.first + '","lastName":"' + $u.last + '","requiredActions":["CONFIGURE_TOTP"]}'
    $json | docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh create users -r openpulse -f -
    kcadm set-password -r openpulse --username $u.kc --new-password $userPass
}

Paso "Registrando Keycloak como proveedor de inicio de sesion en Nextcloud"
occ user_oidc:provider Keycloak --clientid=nextcloud "--clientsecret=$secret" "--discoveryuri=http://${ip}:8081/realms/openpulse/.well-known/openid-configuration" --mapping-uid=preferred_username --unique-uid=0
occ user_oidc:provider

# ---------------------------------------------------------------- 6. Resumen
Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host " ENTORNO LISTO" -ForegroundColor Green
Write-Host "=====================================================================" -ForegroundColor Green
Write-Host " Nextcloud (portal):   http://${ip}:8080    admin / (NC_ADMIN_PASSWORD del .env)"
Write-Host " Keycloak (consola):   http://${ip}:8081    $kcUser / (KC_ADMIN_PASSWORD del .env)"
Write-Host " Collabora:            http://${ip}:9980/hosting/discovery"
Write-Host " Uptime Kuma:          http://localhost:3001"
Write-Host " Asterisk (SIP):       ${ip}:5070 (UDP)   extensiones 1001-1005, clave Clave100X!"
Write-Host ""
Write-Host " Usuarios de Nextcloud y de Keycloak: clave $userPass"
Write-Host "   Nextcloud: wantaurco, rpretel, avallejo, lgil, lparedes"
Write-Host "   Keycloak : willian.antaurco, rosell.pretel, abdon.vallejo, lucia.gil, luis.paredes"
Write-Host ""
Write-Host " Pasos manuales que quedan (ver README.md):" -ForegroundColor Yellow
Write-Host "  - Documentos: entrar a Nextcloud por http://${ip}:8080 (no por localhost)."
Write-Host "  - Login con Keycloak sin HTTPS: activar el modo depuracion solo para probar."
Write-Host "  - Linphone: dominio ${ip}:5070, transporte UDP, codec PCMU activo."
Write-Host "  - Uptime Kuma: crear la cuenta y los monitores."
