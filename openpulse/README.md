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

| Integrante | Rol / Frente técnico | Usuario Nextcloud | Usuario Keycloak | Extensión SIP / SRTP |
|---|---|---|---|---|
| **Willian Antaurco** | Coordinador · Integración y SSO | `wantaurco` | `willian.antaurco` (y `wantaurco.admin`) | `1001` (`Clave1001!`) |
| **Rosell Pretel** | Voz y telefonía IP | `rpretel` | `rosell.pretel` | `1002` (`Clave1002!`) |
| **Abdon Vallejo** | Video, chat y presencia | `avallejo` | `abdon.vallejo` | `1003` (`Clave1003!`) |
| **Lucia Gil** | Documentos colaborativos e IA | `lgil` | `lucia.gil` | `1004` (`Clave1004!`) |
| **Luis Paredes** | Red, QoS, ciberseguridad y monitoreo | `lparedes` | `luis.paredes` | `1005` (`Clave1005!`) |

---

## 3. Batería de Scripts de Verificación para la TA3 (`scripts/`)

- **`scripts/1_auditoria_licencias_sbom.ps1`**: Verifica las imágenes con versión fija en `docker-compose.yml`, genera el archivo SBOM **`sbom_openpulse_ta3.spdx.json`** con **Syft** (`anchore/syft:v1.16.0`) y comprueba el cierre de las 5 acciones correctivas de licencias de la TA2.
- **`asterisk/scripts/qos_experimento_ab.sh`**: Ejecuta el **Experimento Controlado A/B de QoS** (Llamada A con cola única FIFO bajo congestión `iperf3` vs. Llamada B con planificador `tc` HTB + clase `1:10` de prioridad estricta `LLQ` para `DSCP EF = 46` y reglas `nftables`), mostrando los contadores verificables de `tc -s class show dev eth0`.
- **`asterisk/scripts/hardening_security.sh`**: Ejecuta las pruebas de **Hacking Ético (Antes vs. Después)** alineadas con la **Lección 12**:
  1. Comparación de exposición de claves SRTP (`a=crypto`) en SIP-UDP (`:5070`) vs. cifrado de señalización con **SIP-TLS (`:5061`)**.
  2. Simulación de ataque de fuerza bruta `SIP REGISTER` bloqueado automáticamente en `nftables` (`@sip_blacklist`) por `fail2ban` + alerta SIEM para **Wazuh** y rate-limiting anti-DoS (`30 pps`).
- **`scripts/2_mediciones_completas_sla.py`**: Calcula y reporta los **15 indicadores del SLA** de la Sección 3.4, incluyendo los 7 indicadores pendientes de la TA2 (MOS estimado con el Modelo E ITU-T G.107 en 20 llamadas de prueba, % de llamadas dentro de SLA $\ge 95\%$, video 720p WebRTC, latencia de entrega de chat $\le 2\text{ s}$, cambio de presencia $\le 5\text{ s}$, apertura de documentos en Collabora $\le 5\text{ s}$ y prueba real de respaldo/restauración con $\text{RTO} < 1\text{ min}$).
- **`scripts/3_ia_whisper_ollama_acta.py`**: Ejecuta el pipeline local de **Edge AI** (**Whisper** `MIT` + **Ollama** `MIT` con modelo **`Qwen2.5` `Apache-2.0`**) para transcribir una reunión del *Estudio Contable Andes & Asociados S.A.C.* y generar automáticamente el documento **[Acta_Reunion_Andes_IA.md](file:///c:/PUKE/Ing.%20Unificadas/PROYECTO/openpulse_repo/openpulse/Acta_Reunion_Andes_IA.md)**.
