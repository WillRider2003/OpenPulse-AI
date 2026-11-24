#!/usr/bin/env bash
# =====================================================================
#  OpenPulse AI - Configuracion automatica del entorno (Linux / macOS)
#  Uso:  1) Editar .env (HOST_IP y contrasenas)
#        2) bash setup.sh
#  El script se puede ejecutar varias veces: si algo ya existe, lo deja igual.
# =====================================================================
set -u
cd "$(dirname "$0")"

paso() { printf "\n\033[36m==> %s\033[0m\n" "$1"; }
ok()   { printf "    \033[32m%s\033[0m\n" "$1"; }

# ---------------------------------------------------------------- 1. Leer .env
paso "Leyendo configuracion de .env"
[ -f .env ] || { echo "No existe .env. Copia .env.example como .env y completalo."; exit 1; }
getenv() { grep -E "^$1=" .env | head -1 | cut -d= -f2- | tr -d '\r' | sed 's/[[:space:]]*$//'; }
IP=$(getenv HOST_IP)
KC_USER=$(getenv KC_ADMIN)
KC_PASS=$(getenv KC_ADMIN_PASSWORD)
USER_PASS=$(getenv USERS_PASSWORD); [ -n "$USER_PASS" ] && [ "$USER_PASS" != "CAMBIAR" ] || { echo "Define USERS_PASSWORD en .env"; exit 1; }
if [ -z "$IP" ] || [ "$IP" = "PONER_TU_IP" ]; then echo "Define HOST_IP en .env (ver con: ip -4 addr)"; exit 1; fi
ok "HOST_IP = $IP"

# ---------------------------------------------------------------- 2. IP en Asterisk
paso "Actualizando la IP en asterisk/conf/pjsip.conf"
SIP_PASS=$(getenv SIP_PASSWORD)
[ -n "$SIP_PASS" ] && [ "$SIP_PASS" != "CAMBIAR" ] || { echo "Define SIP_PASSWORD en .env"; exit 1; }
# pjsip.conf se genera desde la plantilla y no se sube a Git
sed -e "s/__HOST_IP__/$IP/g" -e "s/__SIP_PASSWORD__/$SIP_PASS/g" asterisk/conf/pjsip.conf.template > asterisk/conf/pjsip.conf
ok "pjsip.conf apunta a $IP (puerto SIP 5070)"

# ---------------------------------------------------------------- 3. Contenedores
paso "Levantando los contenedores (la primera vez tarda varios minutos)"
docker compose up -d --build
docker compose restart asterisk >/dev/null

occ()   { docker compose exec -T -u www-data nextcloud php occ "$@"; }
kcadm() { docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@"; }

paso "Esperando a que Nextcloud termine de instalarse"
for i in $(seq 1 90); do
  occ status --output=json 2>/dev/null | grep -q '"installed":true' && break
  sleep 5
done
occ status --output=json 2>/dev/null | grep -q '"installed":true' || { echo "Nextcloud no respondio. Revisa: docker compose logs nextcloud"; exit 1; }
ok "Nextcloud instalado"

# ---------------------------------------------------------------- 4. Nextcloud
paso "Instalando aplicaciones de Nextcloud (Talk, Office, OpenID Connect)"
for app in spreed richdocuments user_oidc; do occ app:install "$app"; done
occ app:enable user_status
occ config:system:set allow_local_remote_servers --value=true --type=boolean
occ config:system:set trusted_domains 1 --value="$IP"

paso "Creando el grupo openpulse y los usuarios locales"
# nc_usuario|Nombre visible|usuario_keycloak|nombre|apellido|correo
USUARIOS="wantaurco|Willian Antaurco|willian.antaurco|Willian|Antaurco|a20221862@pucp.edu.pe
rpretel|Rosell Pretel|rosell.pretel|Rosell|Pretel|a20206399@pucp.edu.pe
avallejo|Abdon Vallejo|abdon.vallejo|Abdon|Vallejo|a20233429@pucp.edu.pe
lgil|Lucia Gil|lucia.gil|Lucia|Gil|a20233424@pucp.edu.pe
lparedes|Luis Paredes|luis.paredes|Luis|Paredes|a20227191@pucp.edu.pe"
occ group:add openpulse
while IFS='|' read -r NC NOMBRE KC FIRST LAST MAIL; do
  docker compose exec -T -u www-data -e OC_PASS="$USER_PASS" nextcloud php occ user:add --password-from-env --display-name="$NOMBRE" --group=openpulse "$NC" </dev/null
done <<< "$USUARIOS"

paso "Conectando Nextcloud con Collabora"
occ richdocuments:activate-config --wopi-url="http://$IP:9980" --callback-url="http://$IP:8080"

# ---------------------------------------------------------------- 5. Keycloak
paso "Esperando a Keycloak"
for i in $(seq 1 60); do
  kcadm config credentials --server http://localhost:8080 --realm master --user "$KC_USER" --password "$KC_PASS" >/dev/null 2>&1 && break
  sleep 5
done
kcadm config credentials --server http://localhost:8080 --realm master --user "$KC_USER" --password "$KC_PASS" >/dev/null 2>&1 || { echo "No se pudo entrar a Keycloak. Revisa KC_ADMIN y KC_ADMIN_PASSWORD"; exit 1; }
ok "Sesion iniciada en Keycloak"

paso "Creando el realm openpulse"
echo '{"realm":"openpulse","enabled":true,"displayName":"OpenPulse AI"}' | docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh create realms -f -

paso "Creando el cliente nextcloud"
SECRET=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)
CLIENTE='{"clientId":"nextcloud","enabled":true,"protocol":"openid-connect","publicClient":false,"clientAuthenticatorType":"client-secret","secret":"'$SECRET'","standardFlowEnabled":true,"directAccessGrantsEnabled":false,"redirectUris":["http://'$IP':8080/*","http://localhost:8080/*"],"webOrigins":["+"]}'
ID=$(kcadm get clients -r openpulse -q clientId=nextcloud --fields id | grep -o '"id" *: *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
if [ -n "$ID" ]; then
  echo "$CLIENTE" | docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$ID" -r openpulse -f -
  ok "Cliente nextcloud actualizado (secreto nuevo)"
else
  echo "$CLIENTE" | docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh create clients -r openpulse -f -
  ok "Cliente nextcloud creado"
fi

paso "Creando usuarios en Keycloak (con doble factor obligatorio)"
while IFS='|' read -r NC NOMBRE KC FIRST LAST MAIL; do
  echo '{"username":"'$KC'","enabled":true,"emailVerified":true,"email":"'$MAIL'","firstName":"'$FIRST'","lastName":"'$LAST'","requiredActions":["CONFIGURE_TOTP"]}' \
    | docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh create users -r openpulse -f -
  kcadm set-password -r openpulse --username "$KC" --new-password "$USER_PASS" </dev/null
done <<< "$USUARIOS"

paso "Registrando Keycloak como proveedor de inicio de sesion en Nextcloud"
occ user_oidc:provider Keycloak --clientid=nextcloud --clientsecret="$SECRET" \
  --discoveryuri="http://$IP:8081/realms/openpulse/.well-known/openid-configuration" \
  --mapping-uid=preferred_username --unique-uid=0
occ user_oidc:provider

# ---------------------------------------------------------------- 6. Resumen
cat <<EOF

=====================================================================
 ENTORNO LISTO
=====================================================================
 Nextcloud (portal):   http://$IP:8080    admin / (NC_ADMIN_PASSWORD del .env)
 Keycloak (consola):   http://$IP:8081    $KC_USER / (KC_ADMIN_PASSWORD del .env)
 Collabora:            http://$IP:9980/hosting/discovery
 Uptime Kuma:          http://localhost:3001
 Asterisk (SIP):       $IP:5070 (UDP)   extensiones 1001-1005, clave SIP_PASSWORD de .env

 Usuarios de Nextcloud y de Keycloak: clave $USER_PASS
   Nextcloud: wantaurco, rpretel, avallejo, lgil, lparedes
   Keycloak : willian.antaurco, rosell.pretel, abdon.vallejo, lucia.gil, luis.paredes

 Pasos manuales que quedan (ver README.md):
  - Documentos: entrar a Nextcloud por http://$IP:8080 (no por localhost).
  - Login con Keycloak sin HTTPS: activar el modo depuracion solo para probar.
  - Linphone: dominio $IP:5070, transporte UDP, codec PCMU activo.
  - Uptime Kuma: crear la cuenta y los monitores.
EOF
