# OpenPulse AI – Plataforma de Comunicaciones Unificadas (Entrega Final TA3)

Proyecto del curso **TEL139 Ingeniería de Redes Unificadas (PUCP)**. Grupo **OpenPulse AI**.
Cliente del SLA: **Estudio Contable Andes & Asociados S.A.C.** (MYPE de 25 colaboradores: 20 en oficina y 5 remotos).

Este repositorio contiene toda la infraestructura como código, scripts de aprovisionamiento automático, políticas de Calidad de Servicio (**QoS DiffServ `tc` + `nftables`**), controles de **Ciberseguridad y Hacking Ético** y el pipeline de **Edge AI local (`Whisper` + `Ollama`)** con **100 % de licencias de software libre aprobadas por la OSI / FSF**:

| Servicio | Software y versión fijada | Licencia OSI/FSF | URL / Puerto |
|---|---|---|---|
| Portal, chat, videollamadas y presencia | Nextcloud Hub `29.0.8-apache` + Talk | `AGPL-3.0` | `https://IP:8443` (HTTPS vía Caddy) |
| Edición compartida de documentos | Collabora Online `24.04.8.2.1` | `MPL-2.0` | `https://IP:9443` / `http://IP:9980` |
| Inicio de sesión único (SSO) + 2FA TOTP | Keycloak `26.0.5` | `Apache-2.0` | `https://IP:8444` (HTTPS vía Caddy) |
| Directorio central de identidades | OpenLDAP `1.5.0` | `OpenLDAP Public License` | `ldap://IP:389` (`dc=openpulse,dc=local`) |
| Telefonía IP segura y QoS | Asterisk `20 LTS` (Ubuntu `24.04`) | `GPL-2.0` | **SIP-TLS**: `IP:5061/TCP`, SIP-UDP: `IP:5070`, Audio **SRTP** (`DSCP EF=46`): `10000-10100/UDP` |
| Servidor STUN/TURN para WebRTC | coturn `4.6.2-alpine` | `BSD-3-Clause` | `IP:3478/UDP` y `3478/TCP` |
| Proxy inverso TLS y CA interna | Caddy `2.8.4-alpine` | `Apache-2.0` | Puertos HTTPS `8443`, `8444` y `9443` |
| Base de datos relacional | PostgreSQL `16.4-alpine` | `PostgreSQL License` | `5432/TCP` (red interna) |
| Caché en memoria y bloqueo de archivos | **Valkey `8.0.1-alpine`** *(reemplaza a Redis 7.4)* | `BSD-3-Clause` | `6379/TCP` (alias `redis` en red interna) |
| Monitoreo de disponibilidad SLA | Uptime Kuma `1.23.15` | `MIT` | `http://localhost:3001` |
| Recolección de métricas SLA y RTCP | Prometheus `v2.55.1` | `Apache-2.0` | `http://localhost:9090` |
| Tablero visual del SLA para el cliente | **Grafana OSS `11.3.0`** | `AGPL-3.0` | `http://localhost:3000` |
| Asistente de IA local (Edge AI) | Whisper (`MIT`) + Ollama (`MIT`) + Qwen2.5 (`Apache-2.0`) | `MIT` / `Apache-2.0` | Ejecución local (`scripts/3_ia_whisper_ollama_acta.py`) |

---

## 1. Puesta en marcha automatizada

1. **Crear el archivo `.env`** a partir de `.env.example` y colocar en `HOST_IP` la IPv4 de la máquina:
   ```powershell
   Copy-Item .env.example .env
   ```
   Reemplazar cada `CAMBIAR` por una clave propia. `setup.ps1` genera `asterisk/conf/pjsip.conf` desde `pjsip.conf.template`; ni `.env` ni `pjsip.conf` se suben a Git.
2. **Ejecutar el aprovisionamiento completo (`setup.ps1` en Windows o `setup.sh` en Linux):**
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup.ps1
   ```
3. **Ejecutar la batería maestra de pruebas y evidencias de la TA3:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\ejecutar_todas_las_pruebas_ta3.ps1
   ```

---

## 2. Usuarios y extensiones configuradas

| Integrante | Rol / Frente técnico | Usuario Nextcloud | Usuario Keycloak | Extensión SIP / SRTP (clave `SIP_PASSWORD`) |
|---|---|---|---|---|
| **Willian Antaurco** | Coordinador · Integración y SSO | `wantaurco` | `willian.antaurco` (y `wantaurco.admin`) | `1001` |
| **Rosell Pretel** | Voz y telefonía IP | `rpretel` | `rosell.pretel` | `1002` |
| **Abdon Vallejo** | Video, chat y presencia | `avallejo` | `abdon.vallejo` | `1003` |
| **Lucia Gil** | Documentos colaborativos e IA | `lgil` | `lucia.gil` | `1004` |
| **Luis Paredes** | Red, QoS, ciberseguridad y monitoreo | `lparedes` | `luis.paredes` | `1005` |

---

## 3. Scripts de verificación para la TA3 (`scripts/`)

Ningún script contiene resultados escritos en el código: todos muestran lo que miden en ese momento.

- **`scripts/1_auditoria_licencias_sbom.ps1`**: lista las imágenes con versión fija y genera un SBOM SPDX por imagen con **Syft** en la carpeta `sbom/`.
- **`asterisk/scripts/qos_experimento_ab.sh`**: configura la cola del escenario A (`fifo`, tbf) o B (`htb`, clase 1:10 para DSCP EF) y muestra los contadores reales de `tc -s class` y `pjsip show channelstats`. La comparación se hace con dos llamadas Linphone iguales bajo la misma carga de iperf3.
- **`asterisk/scripts/hardening_security.sh`**: aplica nftables (solo puertos del servicio y límite de tasa SIP) y muestra los transportes, la negociación TLS en 5061, el contexto `[default]` y el estado de fail2ban.
- **`asterisk/fail2ban/jail.d/asterisk.local`** y **`asterisk/conf/logger.conf`**: regla de fail2ban (3 fallos en 60 s bloquean 10 min) sobre el registro de Asterisk.
- **`asterisk/scripts/sla_exporter.py`**: publica en `:9105/metrics` la disponibilidad y latencia de los servicios, y el jitter, la pérdida, el RTT y el MOS de las llamadas activas. Sin llamadas, los paneles de voz quedan sin datos.
- **`scripts/2_mediciones_completas_sla.py`**: calcula el MOS (modelo E simplificado), el p95 del jitter y el % de llamadas dentro del SLA desde un CSV de llamadas medidas, y el p95 de los accesos HTTPS.
- **`scripts/3_ia_whisper_ollama_acta.py`**: Ejecuta el pipeline local de **Edge AI** (**Whisper** `MIT` + **Ollama** `MIT` con modelo **`Qwen2.5` `Apache-2.0`**) para transcribir una reunión del *Estudio Contable Andes & Asociados S.A.C.* y generar automáticamente el documento **[Acta_Reunion_Andes_IA.md](Acta_Reunion_Andes_IA.md)**.

## 4. Portal de comunicaciones unificadas

OpenPulse Portal agrega una interfaz propia en **Spring Web / Java 21**. Reúne las
extensiones de Asterisk con apertura directa de Linphone, las salas y la presencia
de Nextcloud Talk, los archivos de Nextcloud con acceso a Collabora, las actas con
IA y las consolas de monitoreo y administración.

Después de aprovisionar el stack, ejecuta `docker compose --profile portal up -d --build portal`
y `docker compose up -d caddy`. Abre `https://IP_DEL_SERVIDOR:8445` con la CA de
Caddy de tu entorno. Consulta [la guía del portal](docs/PORTAL_UNIFICADO.md) para
la demostración, el perfil de IA local y la configuración optativa de Gemini.
