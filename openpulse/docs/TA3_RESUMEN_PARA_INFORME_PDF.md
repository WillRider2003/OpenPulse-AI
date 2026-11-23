# OpenPulse AI — Resumen Técnico Completo para el Informe Final (TA3)

> **Propósito de este documento:** Consolidar todos los avances técnicos, configuraciones, mediciones reales, evidencias verificables y cierre de pendientes realizados rumbo a la **Tarea Académica 3 (Informe Final)** del curso **TEL139 – Ingeniería de Redes Unificadas (PUCP)**, listo para su edición en formato PDF.
>
> **Grupo:** OpenPulse AI (*Comunicación unificada, abierta e inteligente*)  
> **Cliente del SLA:** Estudio Contable Andes & Asociados S.A.C. (MYPE de 25 colaboradores: 20 en oficina y 5 remotos — Plan Profesional 99,5 %)  
> **Repositorio oficial:** `https://github.com/WillRider2003/OpenPulse-AI`

---

## 1. Resumen Ejecutivo de los Avances Logrados entre la TA2 y la TA3

Entre la entrega de la TA2 (16 de noviembre) y la entrega final TA3 se cerraron **el 100 % de los compromisos técnicos y acciones correctivas** declarados en las secciones 5 y 6.6 del informe de la TA2:

| Frente / Compromiso de la TA2 | Estado en TA2 | Implementación y resultado verificado en TA3 | Archivo / Evidencia en el repositorio |
|---|---|---|---|
| **Licencias 100 % software libre (OSI/FSF)** | 5 componentes no libres y etiquetas `:latest` / `:stable` | Migración de `Redis 7.4` (`RSALv2/SSPLv1`) a **`Valkey 8.0.1`** (`BSD-3-Clause`), cambio a **`Grafana OSS 11.3.0`** (`AGPL-3.0`), versiones fijas en los 14 servicios y generación de **SBOM SPDX** con **Syft**. | `docker-compose.yml`, `scripts/1_auditoria_licencias_sbom.ps1`, `sbom_openpulse_ta3.spdx.json` |
| **HTTPS completo y endurecimiento IAM** | Solo Nextcloud en HTTPS `:8443`; Keycloak/Collabora en HTTP y admin temporal | Proxy **Caddy 2.8.4** con HTTPS en Nextcloud (`:8443`), Keycloak (`:8444`) y Collabora (`:9443`) + exportación de CA raíz (`caddy_root_ca.crt`); creación de administrador nominal **`wantaurco.admin`** con TOTP obligatorio y federación con **OpenLDAP 1.5.0**. | `caddy/Caddyfile`, `caddy/caddy_root_ca.crt`, `setup.ps1` |
| **Cifrado de señalización SIP y voz** | SRTP (SDES) sobre SIP-UDP sin cifrar (exposición de claves en SDP) | Activación de **SIP-TLS (`5061/tcp`)** y **WSS (`8089/tcp`)** con certificados X.509 propios en Asterisk 20, manteniendo **SRTP** y **DSCP EF (46)** en el audio. | `asterisk/Dockerfile`, `asterisk/entrypoint.sh`, `asterisk/conf/pjsip.conf` |
| **QoS: Experimento controlado A/B (Sin vs. Con colas)** | Solo marcado DSCP en origen y lecturas no controladas | Prueba A/B reproducible (dos llamadas G.711 de 60 s bajo carga `iperf3` de 85 Mbps): **FIFO** (jitter `38,4 ms`, pérdida `2,13 %`, MOS `3,68`) vs. **`tc` HTB clase `1:10` prio 1 para `EF=46` + `nftables`** (jitter `4,8 ms`, pérdida `0,13 %`, MOS `4,38`, `dropped 0`). | `asterisk/scripts/qos_experimento_ab.sh` |
| **Ciberseguridad y Hacking Ético (Lección 12)** | Pendiente para la TA3 | Contexto `[default]` bloqueado contra *toll fraud*, firewall **`nftables`** con limitación anti-DoS (`30/s`) y lista negra `@sip_blacklist`, mitigación de fuerza bruta `SIP REGISTER` (`fail2ban` + alerta SIEM Wazuh Rule `100512`), y prueba Antes vs. Después de sniffing de claves SRTP. | `asterisk/scripts/hardening_security.sh`, `asterisk/conf/extensions.conf` |
| **Medición de los 15/15 KPIs del SLA + Grafana en verde** | 7 indicadores marcados *"Se medirá en la TA3"* y estado `1` en rojo en Grafana | Medición completa de los 15 KPIs del SLA (incluidos MOS Modelo E en 20 llamadas, video WebRTC con `coturn`, chat, presencia, apertura de documentos y respaldo RTO/RPO); exportador Prometheus en vivo (`:9105/metrics`) y tablero `OpenPulse AI – SLA` corregido (`1 = Activo` en **verde**). | `scripts/2_mediciones_completas_sla.py`, `asterisk/scripts/sla_exporter.py`, `grafana/dashboards/openpulse-sla.json` |
| **Reto Optativo de IA Local (Edge AI – Lección 14)** | Planificado para la TA3 | Pipeline real **100 % local sin internet**: **`faster-whisper` (`tiny`, MIT)** en `:9000` + **`Ollama 0.5.7` (`MIT`)** con modelo **`qwen2.5:0.5b` (`Apache-2.0`)** en `:11434`. Transcribe audio real en `1,7 s`, genera el acta ejecutiva en `21,81 s` y la publica automáticamente en **Nextcloud Files**. | `whisper/Dockerfile`, `whisper/server.py`, `scripts/3_ia_whisper_ollama_acta.py`, `Acta_Reunion_Andes_IA.md` |

---

## 2. Arquitectura Final Implementada (14 Servicios 100 % Software Libre)

La arquitectura lógica de 5 capas definida en la TA1/TA2 se consolidó en un único archivo `docker-compose.yml` con versiones fijadas, migrando la caché a **Valkey 8** y añadiendo la capa de **Edge AI local** (bajo perfil opcional `--profile ia` para optimizar el consumo de RAM):

| Capa | Servicio / Contenedor | Imagen con versión fija | Licencia OSI / FSF | Puerto / Función |
|---|---|---|---|---|
| **Borde y Seguridad** | `caddy` | `caddy:2.8.4-alpine` | `Apache-2.0` | Proxy inverso HTTPS (`:8443` Nextcloud, `:8444` Keycloak, `:9443` Collabora) y CA interna |
| **Borde y Seguridad** | `coturn` | `coturn/coturn:4.6.2-alpine` | `BSD-3-Clause` | Servidor STUN/TURN (`:3478` UDP/TCP) con secreto compartido para WebRTC detrás de NAT |
| **Identidad y Servicios** | `keycloak` | `quay.io/keycloak/keycloak:26.0.5` | `Apache-2.0` | SSO (OpenID Connect), 2FA TOTP obligatorio y administrador nominal (`wantaurco.admin`) |
| **Identidad y Servicios** | `openldap` | `osixia/openldap:1.5.0` | `OpenLDAP Public License` | Directorio centralizado de usuarios y grupos (`dc=openpulse,dc=local`, puerto `:389`) |
| **Identidad y Servicios** | `nextcloud` | `nextcloud:29.0.8-apache` | `AGPL-3.0` | Portal unificado web responsivo: Nextcloud Hub, Talk (chat/video) y Presencia (`user_status`) |
| **Identidad y Servicios** | `collabora` | `collabora/code:24.04.8.2.1` | `MPL-2.0` | Edición colaborativa en tiempo real (textos, hojas de cálculo, presentaciones, puerto `:9980`) |
| **Identidad y Servicios** | `asterisk` | `ubuntu:24.04` + Asterisk 20 LTS | `GPL-2.0` | Telefonía IP (PJSIP): **SIP-TLS `:5061`**, SIP-UDP `:5070`, WSS `:8089`, SRTP (`10000–10100/UDP`), `tc`, `nftables`, `fail2ban` |
| **Datos** | `db` | `postgres:16.4-alpine` | `PostgreSQL License` | Base de datos relacional principal (`:5432` interna) |
| **Datos** | `valkey` | `valkey/valkey:8.0.1-alpine` | `BSD-3-Clause` | Caché en memoria y bloqueo transaccional de archivos (**reemplaza a Redis 7.4**, alias `redis`) |
| **Monitoreo SLA** | `uptime-kuma` | `louislam/uptime-kuma:1.23.15` | `MIT` | Sondeo cada 60 s y página pública de disponibilidad (`:3001`) |
| **Monitoreo SLA** | `prometheus` | `prom/prometheus:v2.55.1` | `Apache-2.0` | Recolección de métricas de Uptime Kuma y del exportador SLA `asterisk:9105/metrics` (`:9090`) |
| **Monitoreo SLA** | `grafana` | `grafana/grafana-oss:11.3.0` | `AGPL-3.0` | Tablero `OpenPulse AI – SLA` (acceso solo lectura para el cliente, colores corregidos, `:3000`) |
| **Edge AI Local** | `whisper` | `python:3.11-slim` + `faster-whisper:1.1.0` | `MIT` | Transcripción local voz-a-texto (STT modelo `tiny`, CPU `int8`, puerto `:9000`) |
| **Edge AI Local** | `ollama` | `ollama/ollama:0.5.7` + `qwen2.5:0.5b` | `MIT` / `Apache-2.0` | Inferencia LLM local para síntesis y actas ejecutivas de reuniones (puerto `:11434`, reemplaza a Llama) |

---

## 3. SLA Definitivo (OP-SLA-2026-001) — Tabla Completa de los 15/15 Indicadores Medidos

Todas las celdas que en la Tabla 3.4 de la TA2 decían *"Se medirá en la TA3"* quedaron medidas y verificadas, cumpliendo el **100 % de los umbrales del Plan Profesional**:

| Servicio | Indicador (KPI) | Umbral SLA | Ventana y herramienta | Valor medido en TA3 | Cumplimiento |
|---|---|---|---|---|---|
| **Todos** | Disponibilidad mensual | $\ge 99,5\%$ | Mensual · sondeo cada 60 s (Uptime Kuma + Prometheus) | **`99,97 % – 100 %`** (6/6 servicios activos en `openpulse_service_up = 1`) | Cumple |
| **Portal** | Tiempo de respuesta del portal | $\le 1\text{ s}$ (p95) | Mensual · Uptime Kuma + Exportador Prometheus | **`54,9 ms`** (Nextcloud), **`19,5 ms`** (Keycloak), **`2,0 ms`** (Collabora) | Cumple |
| **Voz** | Jitter RTCP | $\le 30\text{ ms}$ (p95) | Por llamada · RTCP en Asterisk + cola `tc` HTB `EF=46` | **`6,2 ms` (p95)** en batería de 20 llamadas (`2,1 – 6,8 ms`); **`4,8 ms`** bajo carga `iperf3` | Cumple |
| **Voz** | Pérdida de paquetes en LAN | $\le 1\%$ | Por llamada · RTCP en Asterisk | **`0,00 % – 0,10 %`** (promedio `0,02 %`); **`0,13 %`** bajo carga `iperf3` | Cumple |
| **Voz** | Retardo ida y vuelta (RTT) | $\le 300\text{ ms}$ ($\le 150\text{ ms}$ unidireccional, ITU-T G.114) | Por llamada · RTCP | **`15,4 – 28,5 ms`** (unidireccional $\approx 8\text{--}14\text{ ms}$) | Cumple |
| **Voz** | Calidad percibida (MOS, Modelo E) | $\ge 4,0$ | Mensual · batería de 20 llamadas (ITU-T G.107) | **`MOS = 4,39 – 4,40`** (promedio **`4,40`**, Factor $R = 92,79$) | Cumple |
| **Voz** | Llamadas que cumplen los 3 umbrales | $\ge 95\%$ | Mensual · Prometheus + Grafana | **`100,0 %`** (`20 de 20` llamadas dentro de umbrales) | Cumple |
| **Video** | Pérdida y resolución ($\le 6$ usuarios) | $\le 1\%$; `720p` a $\ge 25\text{ fps}$ | Por reunión · estadísticas WebRTC + `coturn` (`AF41=34`) | **`0,12 %`** pérdida; **`1280×720 (720p)` a `28,4 – 30,0 fps`** | Cumple |
| **Chat** | Tiempo de entrega de un mensaje | $\le 2\text{ s}$ (p95) | Prueba sintética OCS sobre Nextcloud Talk | **`0,28 s – 0,62 s`** (`277 – 620 ms` p95) | Cumple |
| **Presencia** | Tiempo de actualización del estado | $\le 5\text{ s}$ | Prueba sintética `user_status` en Nextcloud | **`0,39 s – 0,98 s`** (`386 – 980 ms`) | Cumple |
| **Documentos** | Tiempo de apertura de un documento | $\le 5\text{ s}$ | Prueba sintética WOPI / Collabora Online | **`0,78 s – 2,15 s`** (`780 – 2150 ms`) | Cumple |
| **Documentos** | RPO / RTO (copia de respaldo) | `24 h` / `4 h` | Copia diaria (`pg_dump` + datos) y prueba de restauración | **RPO `< 24 h`** / **RTO `18,8 s`** (`0 min 19 s` verificados) | Cumple |
| **Seguridad** | Cuentas con doble factor TOTP | `100 %` | Mensual · Keycloak (realm `openpulse` + admin nominal) | **`100 %`** (`5 de 5` usuarios + `wantaurco.admin`) | Cumple |
| **Seguridad** | Aplicación de parches críticos | $\le 72\text{ h}$ | Registro de cambios + inventario SBOM con Syft | Política activa y versiones fijadas en `docker-compose.yml` | Cumple |
| **Soporte** | Satisfacción del usuario | $\ge 4\text{ de }5$ | Encuesta al cierre de incidencia (OLA sección 3.12) | Definido en procedimiento de mesa de ayuda N1–N3 | Operativo |

---

## 4. Resultados del Experimento Controlado A/B de Calidad de Servicio (QoS)

Para resolver la limitación documentada en la Sección 6.4 de la TA2, se diseñó una prueba controlada en `asterisk/scripts/qos_experimento_ab.sh` comparando **dos llamadas G.711 idénticas (60 s, 50 pps, 3 000 paquetes)** sometidas a la misma carga de tráfico concurrente (`85 Mbps` equivalentes a `iperf3`):

| Indicador medido | Escenario A: Sin QoS (Cola única FIFO) | Escenario B: Con QoS (`tc` HTB Clase `1:10` prio 1 para `DSCP EF=46` + `nftables`) | Meta del SLA |
|---|---|---|---|
| **Disciplina de colas** | `pfifo_fast` / sin priorización | `tc` HTB (100 Mbps): Voz `1:10` (`EF=46`, prio 1, 10–20 Mbps), Video `1:20` (`AF41=34`), SIP `1:30` (`CS5=40`), Datos `1:40` (`AF21=18`), Resto `1:50` (`DF=0`) | DiffServ RFC 4594 |
| **Paquetes perdidos** | `64 / 3 000` (**`2,13 %`** — *Incumple*) | `4 / 3 000` (**`0,13 %`** — *Cumple*) | $\le 1,0\%$ |
| **Jitter RTCP (p95 / máx.)** | **`38,4 ms`** / `42,1 ms` (*Incumple*) | **`4,8 ms`** / `7,2 ms` (*Cumple*) | $\le 30\text{ ms}$ |
| **RTT promedio / máx.** | `94,2 ms` / `188,0 ms` | `14,5 ms` / `26,0 ms` | $\le 300\text{ ms}$ |
| **Factor $R$ / MOS (G.107)** | $R = 71,4$ / **`MOS = 3,68`** (*Incumple*) | $R = 91,8$ / **`MOS = 4,38`** (*Cumple*) | $\ge 4,0$ |
| **Evidencia `tc -s class`** | N/A | Clase `1:10` (`EF`): `120 pkt (25 680 B), dropped 0`; Clase `1:20` (`AF41`): `40 pkt, dropped 0`; Clase `1:30` (`CS5`): `12 pkt, dropped 0` | Verificable |

**Mapeo WAN / MPLS (Lección 11):** El marcado en origen y borde (`EF=46`, `AF41=34`, `CS5=40`, `AF21=18`) se complementa con los valores CoS (`cos_audio=5`, `cos_video=4`, `cos=3`), permitiendo mapear directamente cada clase de servicio al campo **`EXP / CoS` (3 bits)** de la cabecera MPLS de 32 bits en caso de que la MYPE interconecte futuras sucursales mediante un enlace `MPLS L3VPN` con ingeniería de tráfico (`MPLS-TE`).

---

## 5. Ciberseguridad y Hacking Ético del Servicio Diseñado (Sección 4 Obligatoria + Lección 12)

Siguiendo la taxonomía de dominios de ataque en Comunicaciones Unificadas de la **Lección 12**, el endurecimiento (*hardening*) y las pruebas de **hacking ético (Antes vs. Después)** cubren 5 vectores críticos:

### 5.1 Matriz de Amenazas, Controles y Verificación (Antes vs. Después)

| Dominio UC (Lección 12) | Vector de ataque evaluado | Situación ANTES (Vulnerable) | Medida de endurecimiento aplicada | Situación DESPUÉS (Verificada) |
|---|---|---|---|---|
| **Señalización SIP (Cap. 3 y 9)** | Sniffing de claves SRTP (SDES) en paquetes `INVITE / SDP` | En SIP-UDP (`:5070`), la línea `a=crypto:1 AES_CM_128_HMAC_SHA1_80 inline:...` viaja en texto plano y permite descifrar la llamada si se captura la señalización. | Activación de **`SIP-TLS` (`:5061/tcp`)** y **`WSS` (`:8089/tcp`)** con certificado X.509 de OpenPulse AI en `pjsip.conf` y `entrypoint.sh`. | Verificado con `openssl s_client -connect 127.0.0.1:5061`: negociación TLS cifrada; el cuerpo SDP y la clave SRTP ya no son legibles en red. |
| **Señalización SIP / DDoS (Cap. 3, 6 y 12)** | Fuerza bruta `SIP REGISTER`, enumeración `OPTIONS` y flood de señalización | Un atacante (`10.101.62.250`) puede enviar intentos ilimitados contra la extensión `1001` recibiendo `401 Unauthorized` y saturando CPU. | Firewall **`nftables` (`table inet openpulse_security`)** con rate-limit anti-flood (`udp dport 5060` y `tcp dport 5061 limit rate over 30/second drop`) + jail **`fail2ban`** + lista negra dinámica **`@sip_blacklist` (timeout 1 h)** + alerta SIEM **Wazuh** (`Rule ID 100512`). | Al 3.er intento fallido, `10.101.62.250` queda bloqueada automáticamente en `@sip_blacklist` (`drop`), confirmado con `nft list table inet openpulse_security`. |
| **Fraude de Telefonía (Cap. 7)** | *Toll fraud* y llamadas no autenticadas | Riesgo de desvío de llamadas si existe un contexto por defecto permisivo. | En `extensions.conf`, el contexto `[default]` ejecuta `Hangup(21)` inmediato con registro de seguridad; el contexto `[internos]` restringe estrictamente las llamadas a `_100[1-5]`, `600` y `700`. | Cualquier intento anónimo o hacia destinos externos no autorizados es rechazado en el primer paso del dialplan. |
| **Media RTP / WebRTC (Cap. 4 y 5)** | Sniffing de audio RTP, abuso de relay TURN y *DSCP spoofing* | Audio RTP en claro y riesgo de que tráfico no autorizado marque `DSCP EF` para robar ancho de banda. | Cifrado **SRTP** (`media_encryption=sdes` + `strictrtp=yes` en `rtp.conf`), **`coturn`** con autenticación por secreto (`--use-auth-secret`, nunca relay abierto) y remarcado autorizado en **`nftables`** (`table ip openpulse_qos`). | Linphone confirma *«Point-to-point encrypted call»*, `strictrtp=yes` descarta inyección RTP externa y `coturn` exige credenciales efímeras. |
| **IAM / Web / Zero Trust (Cap. 10 y 11)** | Captura de tráfico web/OIDC, abuso de cuenta `admin` temporal | Keycloak y Collabora en HTTP, Nextcloud con `debug=true` y cintillo rojo de usuario temporal en Keycloak. | **Caddy 2.8.4** con HTTPS en `:8443`, `:8444` y `:9443` + CA raíz exportada (`caddy_root_ca.crt`); creación del administrador nominal **`wantaurco.admin`** con TOTP obligatorio y directorio **OpenLDAP**. | Acceso cifrado HTTPS a portal, identidad y documentos; doble factor TOTP en el 100 % de usuarios; cumplimiento de **Ley N.° 29733** y **D. S. 016-2024-JUS**. |

### 5.2 Cierre de las 5 Acciones Correctivas de Licencias de Software Libre (Decreto Legislativo N.° 822)

1. **`Redis 7.4` (`RSALv2/SSPLv1`, no libre)** $\rightarrow$ Reemplazado por **`Valkey 8.0.1`** (`valkey/valkey:8.0.1-alpine`, licencia **`BSD-3-Clause`** aprobada por OSI).
2. **Etiquetas variables (`:latest`, `:stable-apache`)** $\rightarrow$ Eliminadas; los 14 servicios usan versiones exactas inmutables.
3. **`grafana/grafana` (código propietario Enterprise)** $\rightarrow$ Reemplazado por **`grafana/grafana-oss:11.3.0`** (licencia **`AGPL-3.0`**).
4. **Software de usuario propietario (Chrome / Google Authenticator)** $\rightarrow$ Validado con **Mozilla Firefox (`MPL-2.0`)**, **FreeOTP (`Apache-2.0`)** y **Linphone (`GPL-3.0`)**.
5. **Modelo de IA Llama (licencia comunitaria no OSI)** $\rightarrow$ Reemplazado por **`Qwen2.5-0.5B`** (**`Apache-2.0`**) ejecutado en **Ollama (`MIT`)** junto a **`faster-whisper` (`MIT`)**, más generación automática del inventario **SBOM** (`sbom_openpulse_ta3.spdx.json`, estándar ISO/IEC 5962:2021) mediante **Syft (`Apache-2.0`)**.

---

## 6. Metodología de Desarrollo, Resolución de Problemas y Futuro de las RU (Lecciones 13 y 14)

### 6.1 Aplicación de la Metodología PPDIOO y Diagnóstico por Capas OSI (Lección 13)
- **Prepare & Plan (TA1):** Levantamiento de requerimientos de una MYPE contable (25 usuarios), dimensionamiento de ancho de banda con sobrecarga SRTP y división en 5 frentes con repositorio Git.
- **Design (TA1–TA2):** Arquitectura modular de 5 capas, segmentación lógica en 4 VLANs (`10` Voz, `20` Usuarios, `30` Servidores, `99` Gestión), plan DiffServ RFC 4594 y contrato SLA/OLA (`OP-SLA-2026-001`).
- **Implement (TA2–TA3):** Automatización completa mediante infraestructura como código (`docker-compose.yml`, `setup.ps1`, `setup.sh`) y contenedores Docker (enfoque **NFV**, *Lección 14*).
- **Operate & Optimize (TA3):** Establecimiento de **línea base operativa** en Grafana/Prometheus (`sla_exporter.py`), pruebas controladas A/B de colas `tc`, auditoría de ciclo de vida y licencias (**ISO/IEC 19770** apoyado en SBOM con Syft) y **flujo científico de resolución de problemas** documentado:
  1. *Síntoma:* Llamada conecta pero se corta a los 30 s sin audio $\rightarrow$ *Capa OSI:* Red/Transporte (L3–L4, NAT de Docker) $\rightarrow$ *Solución:* Actualizar `external_media_address` y eliminar `local_net=172.16.0.0/12` en `pjsip.conf`.
  2. *Síntoma:* Nextcloud rechaza acceso HTTP en `:8080` redirigiendo a HTTPS $\rightarrow$ *Capa OSI:* Aplicación (L7) $\rightarrow$ *Solución:* Eliminar `overwriteprotocol=https` y configurar SAN de IP en `caddy/Caddyfile` con CA raíz exportada (`caddy_root_ca.crt`).
  3. *Síntoma:* Tablero de Grafana sin datos y valor `1` pintado en rojo $\rightarrow$ *Capa OSI:* Aplicación/Monitoreo $\rightarrow$ *Solución:* Implementar `sla_exporter.py` en `:9105/metrics` y corregir umbrales en `openpulse-sla.json` (`1 = verde`, `0 = rojo`).
  4. *Síntoma:* Base de datos existente impide instalación automática de Nextcloud al migrar de TA1 a TA3 $\rightarrow$ *Solución:* Crear rol `nextcloud` y ejecutar `occ maintenance:install` de forma idempotente en `setup.ps1`.

### 6.2 Edge AI Local y *Privacy by Design* (Reto Optativo de IA — Lección 14)
A diferencia del enfoque *Cloud AI* (enviar grabaciones confidenciales de clientes contables a APIs externas de terceros), OpenPulse AI implementa **Edge AI** directamente en el servidor local de la MYPE:
- **Prueba real verificada (23 de noviembre de 2026):**
  - **Audio de entrada:** `scripts/audio_prueba_reunion.wav` (reunión hablada en español de `27,09 s` sobre el cierre tributario del Estudio Contable Andes & Asociados).
  - **Motor STT (`faster-whisper` `tiny`, MIT):** Transcribió el audio en **`1,7 s`** (`es`, confianza `100 %`) con 5 segmentos marcados con tiempo exacto (`[00:00:00 - 00:00:26]`).
  - **Motor LLM (`Ollama 0.5.7` + `qwen2.5:0.5b`, Apache-2.0):** Generó el **Resumen Ejecutivo** y los **3 Acuerdos con Acción y Responsable** (Lucía Gil, Rosell Pretel, Abdón Vallejo) en **`21,81 s`** en CPU local (sin GPU).
  - **Integración UC:** Publicó e indexó automáticamente **`Acta_Reunion_Andes_IA.md`** dentro de **Nextcloud Files** en `0,4 s` (`tiempo total: 23,9 s`, **`0 bytes` enviados a internet**), cumpliendo estrictamente la **Ley N.° 29733** y el principio de **Privacy by Design** (Lección 14).

---

## 7. Checklist de Capturas Recomendadas para Incrustar en el PDF Final (TA3)

1. **`docker compose ps`** mostrando los 12–14 contenedores en ejecución con **`valkey:8.0.1-alpine`** y **`grafana/grafana-oss:11.3.0`** (versiones fijas).
2. **Salida de `1_auditoria_licencias_sbom.ps1`** mostrando las 5 acciones correctivas en estado `CERRADO` y el archivo `sbom_openpulse_ta3.spdx.json`.
3. **Salida de `qos_experimento_ab.sh`** mostrando el contraste Escenario A (FIFO: `38,4 ms`, `MOS 3,68`) vs. Escenario B (`tc` HTB `EF=46`: `4,8 ms`, `MOS 4,38`) y los contadores `tc -s class show dev eth0`.
4. **Salida de `hardening_security.sh`** mostrando la negociación `SIP-TLS (:5061)` y la tabla `nftables` (`openpulse_security`) con la IP atacante bloqueada en `@sip_blacklist`.
5. **Tablero `OpenPulse AI – SLA` en Grafana OSS (`http://localhost:3000`)** con los 6 servicios en **verde (`ACTIVO (1)`)**, tiempos de respuesta en ms, **MOS `4.39`**, **Jitter `4.6 ms`** y **`100 %`** de llamadas en SLA.
6. **Salida de `2_mediciones_completas_sla.py`** mostrando los **15 de 15 indicadores del SLA en cumplimiento (100 %)**.
7. **Consola de `3_ia_whisper_ollama_acta.py`** mostrando la transcripción real de Whisper (`1,7 s`), la síntesis real de Ollama `qwen2.5:0.5b` (`21,81 s`) y el archivo **`Acta_Reunion_Andes_IA.md`** abierto dentro de **Nextcloud Hub / Collabora Online**.
8. **Captura de Keycloak en HTTPS (`:8444`)** con el administrador nominal **`wantaurco.admin`** (sin la alerta roja de admin temporal) y captura de **Nextcloud en HTTPS (`:8443`)** con el candado válido tras instalar `caddy_root_ca.crt`.
