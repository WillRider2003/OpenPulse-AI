# Avance TA2 - OpenPulse AI

## Qué funciona
- SSO: Keycloak (realm openpulse) a Nextcloud por OIDC, con doble factor (OTP).
- Voz: Asterisk con SRTP (media_encryption=sdes), marcado DSCP (tos_audio=ef, tos_video=af41, tos=cs5 en el transporte).
- HTTPS del portal con Caddy en el puerto 8443 (Caddyfile.example).
- Monitoreo: Uptime Kuma; Prometheus y Grafana (carpeta monitoring) leen las métricas de Uptime Kuma.

## Levantarlo
1. copy .env.example .env, poner HOST_IP y contraseñas propias.
2. powershell -ExecutionPolicy Bypass -File .\setup.ps1
3. Caddy: copiar Caddyfile.example a Caddyfile, cambiar TU_IP por la IP real y levantar el contenedor caddy:2 en la red openpulse_default.
4. Monitoring: copiar prometheus.yml.example a prometheus.yml con las credenciales de Uptime Kuma y ejecutar docker compose up -d dentro de monitoring.

## Si cambia la IP (pasa al cambiar de red)
1. Actualizar HOST_IP en .env y ejecutar setup.ps1.
2. occ config:system:set trusted_domains N --value=IP_NUEVA
3. Regenerar el Caddyfile y recrear el contenedor de Caddy.
4. En Keycloak, cliente nextcloud: agregar https://IP_NUEVA:8443/* a Valid redirect URIs.
5. En Linphone, cambiar el dominio SIP a IP_NUEVA:5070.

## Problemas ya resueltos
- Llamadas mudas que se cortan a los 30 s: Asterisk anunciaba la IP vieja (external_media_address).
- Nextcloud con OIDC exige HTTPS o debug=true (occ config:system:set debug --value=true --type=boolean).
- Uptime Kuma con error 400: agregar "nextcloud" a trusted_domains.
- Puertos de Docker que dejan de responder: docker compose up -d --force-recreate SERVICIO.
- NUNCA usar docker compose down -v (borra el historial de Uptime Kuma).

## Pendiente para la TA3
OpenLDAP, TLS en señalización SIP y en Keycloak, VLAN, colas tc, nftables, prueba con y sin QoS,
hacking ético (nmap, fail2ban, Wazuh, escaneo SIP), IA (Whisper y Ollama), Jitsi y coturn,
migrar Redis a Valkey (licencia), monitores sobre puertos publicados y HTTPS.

## Seguridad
No subir .env ni prometheus.yml. Las contraseñas de extensiones de pjsip.conf son solo de laboratorio.
