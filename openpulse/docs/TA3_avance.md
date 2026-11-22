# Avance TA3 - OpenPulse AI

## Mejoras implementadas para la Entrega Final (TA3)
- **Licencias 100 % libres (OSI/FSF) y versiones fijadas:**
  - Migración de `redis:7-alpine` (Redis 7.4 con licencia RSALv2/SSPLv1) a **`valkey/valkey:8.0.1-alpine`** (`BSD-3-Clause`) con alias `redis` en la red de Docker.
  - Cambio a **`grafana/grafana-oss:11.3.0`** (`AGPL-3.0`) y fijación de versiones exactas en todos los contenedores (`postgres:16.4-alpine`, `nextcloud:29.0.8-apache`, `collabora/code:24.04.8.2.1`, `keycloak:26.0.5`, `caddy:2.8.4-alpine`, `coturn:4.6.2-alpine`, `openldap:1.5.0`, `uptime-kuma:1.23.15`, `prometheus:v2.55.1`).
  - Generación automatizada del inventario **SBOM SPDX** (`sbom_openpulse_ta3.spdx.json`) con **Syft** (`scripts/1_auditoria_licencias_sbom.ps1`).
- **Ciberseguridad y Hacking Ético (Lección 12):**
  - **HTTPS completo con Caddy (`caddy/Caddyfile`):** Portal Nextcloud en `:8443`, Keycloak en `:8444` y Collabora en `:9443`, permitiendo desactivar el modo de depuración (`debug=false`) en Nextcloud y crear el administrador nominal `wantaurco.admin` con doble factor TOTP en Keycloak.
  - **Señalización SIP sobre TLS (`:5061/tcp`):** Generación automática de certificados X.509 en `asterisk/entrypoint.sh` y transporte `[transport-tls]` en `pjsip.conf` para evitar la exposición en texto claro de las claves SRTP (SDES).
  - **Endurecimiento y Hacking Ético (`asterisk/scripts/hardening_security.sh`):** Contexto `[default]` bloqueado contra llamadas anónimas (prevención de *toll fraud*), firewall `nftables` con limitación de tasa anti-DoS (`30/second`) y bloqueo automático de fuerza bruta `SIP REGISTER` (`@sip_blacklist` + `fail2ban` + alerta SIEM Wazuh).
- **Calidad de Servicio (QoS) y Experimento Controlado A/B (`asterisk/scripts/qos_experimento_ab.sh`):**
  - Comparación reproducible entre dos llamadas bajo congestión: **Escenario A** (cola FIFO por defecto sin priorización) vs. **Escenario B** (planificador `tc` HTB con clase `1:10` de prioridad estricta `prio 1` para `DSCP EF = 46` y marcado `nftables`), verificando contadores con `tc -s class show dev eth0`.
- **Mediciones completas del SLA (`scripts/2_mediciones_completas_sla.py`):**
  - Completa los 7 indicadores pendientes de la Tabla 3.4 de la TA2: MOS estimado con Modelo E (ITU-T G.107) en batería de 20 llamadas de prueba, % de llamadas dentro de SLA ($\ge 95\%$), pérdida y resolución de video WebRTC (720p a $\ge 25\text{ fps}$ con `coturn`), tiempo de entrega de mensajes de chat ($\le 2\text{ s}$), cambio de presencia ($\le 5\text{ s}$), apertura de documentos en Collabora ($\le 5\text{ s}$) y prueba cronometrada de respaldo y restauración ($\text{RTO} \le 4\text{ h}$).
  - Corrección de la escala de colores en el tablero `OpenPulse AI – SLA` de Grafana (`1 = Activo` en verde, `0 = Caído` en rojo).
- **Asistente de IA Local – Edge AI (`scripts/3_ia_whisper_ollama_acta.py`):**
  - Transcripción local con **Whisper** (`MIT`) y generación de acta ejecutiva con **Ollama** (`MIT`) y modelo **`Qwen2.5`** (`Apache-2.0`), generando `Acta_Reunion_Andes_IA.md` bajo el principio de *Privacy by Design* (Lección 14).
