# Guía Exacta de Despliegue y Demostración en Vivo — Laboratorio V305 (OpenPulse AI)

> **Propósito de este documento:** Manual operativo paso a paso para que el equipo **OpenPulse AI** levante la plataforma sin errores en el **Laboratorio V305** y ejecute en orden todas las demostraciones en vivo frente a los Jefes de Práctica (JPs) y el profesor.

---

## 1. Arquitectura de Despliegue en el Salón V305 (Cómo organizarse en 2 minutos)

**Regla de oro:** Solo **UNA computadora** necesita tener Docker corriendo (la **PC Servidor**). Las demás PCs del laboratorio V305 y sus celulares actúan como **Clientes** conectados a la misma red local (Ethernet o Wi-Fi del laboratorio) sin instalar Docker.

- **PC Servidor (1 máquina):** Puede ser una PC del laboratorio V305 con Docker Desktop/Engine **o** la laptop del equipo donde ya están descargadas todas las imágenes de Docker (opción recomendada para ahorrar 15 minutos de descarga en el salón).
- **PCs Clientes (2 a 4 PCs del V305 + 1 celular):** Solo necesitan navegador web (**Firefox** o Chrome) y **Linphone** instalado para las pruebas de voz.

---

## 2. Puesta en Marcha en la PC Servidor (Paso a Paso)

### Paso 1: Averiguar la dirección IPv4 de la PC Servidor en el laboratorio
Abrir **Windows PowerShell** en la PC Servidor y ejecutar:
```powershell
ipconfig
```
Buscar la línea **`Dirección IPv4`** del adaptador conectado a la red del salón (**Ethernet** o **Wi-Fi**). A partir de aquí llamaremos a esa IP **`IP_LAB`** (ejemplo: `10.101.62.44`).

### Paso 2: Clonar o actualizar el repositorio de GitHub
- Si es una PC nueva del V305:
  ```powershell
  git clone https://github.com/WillRider2003/OpenPulse-AI.git
  cd OpenPulse-AI\openpulse
  ```
- Si es una laptop que ya tiene la carpeta clonada:
  ```powershell
  cd "C:\PUKE\Ing. Unificadas\PROYECTO\openpulse_repo\openpulse"
  git pull origin main
  ```

### Paso 3: Configurar la IP del laboratorio en `.env`
```powershell
if (-not (Test-Path ".env")) { Copy-Item .env.example .env }
notepad .env
```
En el archivo `.env`, cambiar únicamente la primera línea por la IP real del salón:
```env
HOST_IP=IP_LAB
```
Guardar (`Ctrl + S`) y cerrar el Bloc de notas.

### Paso 4: Asegurar que Docker Desktop esté encendido y ejecutar `setup.ps1`
Verificar que **Docker Desktop** muestre **"Engine running"** en verde y ejecutar:
```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```
**Qué configura automáticamente `setup.ps1`:**
1. Actualiza `IP_LAB` en `asterisk/conf/pjsip.conf` y `caddy/Caddyfile`.
2. Levanta los 12 contenedores base (`Nextcloud`, `Collabora`, `Keycloak`, `OpenLDAP`, `Asterisk`, `coturn`, `Caddy`, `PostgreSQL`, `Valkey 8`, `Uptime Kuma`, `Prometheus`, `Grafana OSS`).
3. Instala Talk, Nextcloud Office (Collabora), OpenID Connect y Presencia; crea el grupo `openpulse` y los 5 usuarios (`wantaurco`, `rpretel`, `avallejo`, `lgil`, `lparedes`, clave `OpenPulse2026!`).
4. Conecta Nextcloud con Collabora Online, `coturn` y el botón **«Iniciar sesión con Keycloak»**.
5. Activa las colas de prioridad **QoS (`tc` HTB)**, el firewall **`nftables`** y el exportador Prometheus en vivo (`:9105/metrics`).

### Paso 5: Encender los contenedores de Inteligencia Artificial Local (Edge AI)
Para activar **Whisper** (`:9000`) y **Ollama** (`:11434`):
```powershell
docker compose --profile ia up -d
```
*(Solo la **primera vez** en una PC nueva del V305, descargar el modelo libre Apache-2.0 con: `docker exec openpulse-ollama-1 ollama pull qwen2.5:0.5b`. En la laptop donde ya se probó, el modelo ya está guardado en el disco y arranca en 2 segundos sin internet).*

### Paso 6 (Opcional para candado verde HTTPS sin advertencias en Windows):
Exportar e instalar el certificado de la Autoridad Interna de Caddy en la PC del demo:
```powershell
docker cp openpulse-caddy-1:/data/caddy/pki/authorities/local/root.crt .\caddy\caddy_root_ca.crt
```
Hacer doble clic en `caddy\caddy_root_ca.crt` $\rightarrow$ **Instalar certificado** $\rightarrow$ **Usuario actual** $\rightarrow$ **Colocar todos los certificados en el siguiente almacén** $\rightarrow$ **Entidades de certificación raíz de confianza** $\rightarrow$ **Finalizar**, y reiniciar el navegador.

---

## 3. Credenciales y Enlaces Rápidos para el Día de la Demo

| Servicio | Dirección URL (reemplazar `IP_LAB`) | Usuario | Contraseña |
|---|---|---|---|
| **Nextcloud (HTTP – ideal Collabora)** | `http://IP_LAB:8080/login` | `wantaurco`, `rpretel`, `avallejo`, `lgil`, `lparedes` | `OpenPulse2026!` |
| **Nextcloud (HTTPS vía Caddy)** | `https://IP_LAB:8443/login` | *(mismos usuarios o botón Keycloak)* | `OpenPulse2026!` |
| **Keycloak (SSO + 2FA)** | `http://IP_LAB:8081` o `https://IP_LAB:8444` | `willian.antaurco`, `abdon.vallejo`, etc. (admin: `wantaurco.admin` / `admin`) | Usuarios: `OpenPulse2026!` / Admin: `OpenPulseAdmin2026!` |
| **Grafana OSS (Tablero SLA en verde)** | `http://IP_LAB:3000` | `admin` | `OpenPulseAdmin2026!` |
| **Prometheus (Métricas SLA)** | `http://IP_LAB:9090/targets` | *(acceso directo)* | — |
| **Uptime Kuma (Disponibilidad)** | `http://IP_LAB:3001` | *(cuenta creada en el navegador)* | — |
| **Asterisk (Linphone SIP / SRTP)** | Dominio: `IP_LAB:5070` (UDP) o `IP_LAB:5061` (TLS) | Extensiones `1001` a `1005` | `Clave1001!` a `Clave1005!` |

---

## 4. Secuencia Exacta de las 7 Demostraciones en Vivo frente a los JPs

### Demo 1 — Inicio de Sesión Único (SSO) con Doble Factor TOTP *(Willian Antaurco)*
1. Abrir navegador (preferiblemente **Mozilla Firefox**, software libre) en una ventana nueva en **`https://IP_LAB:8443/login`** (o `http://IP_LAB:8080/login`).
2. Hacer clic en **«Iniciar sesión con Keycloak»** (en la parte inferior del formulario).
3. Ingresar con `willian.antaurco` / `OpenPulse2026!`, validar el código de 6 dígitos en **FreeOTP** (o Google Authenticator) y mostrar el ingreso automático a Nextcloud Hub.
4. En otra pestaña (`http://IP_LAB:8081` o `https://IP_LAB:8444`), mostrar la consola de Keycloak con el realm **`openpulse`**, los 5 usuarios y el administrador nominal **`wantaurco.admin`**.

### Demo 2 — Telefonía IP Cifrada (SRTP + SIP-TLS) y Calidad de Voz *(Rosell Pretel)*
1. En **PC Cliente 1**, abrir **Linphone** con la cuenta `1001` (`Clave1001!`, dominio `IP_LAB:5070`, transporte `UDP`, códec **`PCMU`** activo y en *Preferencias $\rightarrow$ Llamadas $\rightarrow$ Cifrado de medios* elegir **`SRTP`**).
2. En **PC Cliente 2 o celular**, abrir **Linphone** con la cuenta `1002` (`Clave1002!`, dominio `IP_LAB:5070`, **`SRTP`** activo).
3. Verificar registro en el PowerShell del Servidor:
   ```powershell
   docker compose exec asterisk asterisk -rx "pjsip show contacts"
   ```
   *(Debe mostrar `1001` y `1002` en estado **`Avail`**).*
4. Llamar de `1001` a `1002` (o marcar **`600`** para la prueba de eco). Señalar en pantalla de Linphone el ícono de candado azul **«Point-to-point encrypted call»**.
5. **Mientras la llamada está activa**, ejecutar en el PowerShell del Servidor para mostrarle al JP el **Jitter ($\le 30\text{ ms}$), Pérdida ($\le 1\%$) y RTT** en vivo:
   ```powershell
   docker compose exec asterisk asterisk -rx "pjsip show channelstats"
   ```

### Demo 3 — Chat, Videollamada WebRTC y Presencia Automática *(Abdón Vallejo)*
1. En **PC Cliente 1** (sesión de `avallejo`) y **PC Cliente 2** (sesión de `lgil`), entrar a la pestaña **Talk** en Nextcloud (`http://IP_LAB:8080` o `https://IP_LAB:8443`).
2. Enviar mensajes en el chat grupal para mostrar la persistencia y latencia menor a 1 segundo.
3. Cambiar manualmente el estado de presencia en la esquina superior derecha (**En línea** $\rightarrow$ **No molestar**) y mostrar cómo se actualiza al instante en la otra PC.
4. Iniciar una **llamada / videollamada en Talk**: mostrar desde una tercera cuenta que el estado cambia **automáticamente a «En una llamada»** sin intervención manual.
   - *(Si usan HTTP `http://IP_LAB:8080` en Chrome y bloquea la cámara/micrófono: entrar por **`https://IP_LAB:8443`** o habilitar `chrome://flags/#unsafely-treat-insecure-origin-as-secure` agregando `http://IP_LAB:8080`).*

### Demo 4 — Edición Compartida de Documentos en Tiempo Real *(Lucía Gil)*
1. **Importante:** Entrar a Nextcloud por **`http://IP_LAB:8080`** (con la IP real, nunca `localhost`).
2. Con `lgil`, ir a **Archivos (Files)** $\rightarrow$ **`+ Nuevo`** $\rightarrow$ **`Nuevo documento`** (ej. `Cierre_Andes_V305.odt`).
3. Compartirlo con el grupo **`openpulse`** con permiso de edición.
4. Abrir ese mismo documento simultáneamente en **2 o 3 PCs del laboratorio** y escribir a la vez frente al JP para demostrar la co-edición sin bloqueos ni conflictos (Lección 10).

### Demo 5 — Prueba desde Cero de la Inteligencia Artificial Local (`Whisper` + `Ollama`) *(Lucía Gil / Todo el equipo)*
Demostrarle al JP que funciona **100 % en local con un audio nuevo grabado frente a él** (sin usar ChatGPT ni enviar datos a internet):
1. Abrir la **Grabadora de sonidos** de Windows (o grabar una nota de voz en el celular) y pedirle al JP que dicte 2 acuerdos cualquiera durante 10–20 segundos. Guardar el archivo (ej. `demo_jp.m4a` o `demo_jp.wav`).
2. En PowerShell de la PC Servidor, ejecutar:
   ```powershell
   python .\scripts\3_ia_whisper_ollama_acta.py --audio "C:\ruta\a\demo_jp.m4a" --salida "Acta_Demo_V305.md"
   ```
   *(Plan B si hay mucho ruido en el salón: `python .\scripts\3_ia_whisper_ollama_acta.py --texto "Acuerdo 1: ... Acuerdo 2: ..." --salida "Acta_Demo_V305.md"`, o sin argumentos para usar `scripts\audio_prueba_reunion.wav`).*
3. En ~20 segundos, el JP verá en consola la **transcripción literal de Whisper (`MIT`)**, la **síntesis y lista de acuerdos generada por Ollama `qwen2.5:0.5b` (`Apache-2.0`)**, y el mensaje **`[OK] 'Acta_Demo_V305.md' ya esta visible en Nextcloud Files`**.
4. Actualizar (`F5`) la pestaña de **Archivos (Files)** en Nextcloud en cualquier PC del salón y abrir **`Acta_Demo_V305.md`** en vivo.

### Demo 6 — Monitoreo del SLA en Tiempo Real *(Luis Paredes)*
1. Abrir **Grafana OSS** en **`http://IP_LAB:3000`** (`admin` / `OpenPulseAdmin2026!`) $\rightarrow$ **Dashboards $\rightarrow$ OpenPulse AI – SLA** (poner rango `Last 15 minutes` y `Refresh 10s`).
2. Mostrar los **6 servicios en verde (`ACTIVO (1)`)**, sus curvas de latencia real en ms, el medidor **MOS (`4.39`)**, **Jitter (`4.6 ms`)**, **`100 %`** de llamadas en SLA y los KPIs de colaboración.
3. Mostrar **Prometheus** (`http://IP_LAB:9090/targets` con `openpulse-sla-exporter` en **`UP`**) y **Uptime Kuma** (`http://IP_LAB:3001`).

### Demo 7 — Licencias (SBOM), Experimento QoS A/B y Hacking Ético *(Luis Paredes)*
En PowerShell de la PC Servidor, ejecutar la batería completa (o cada script por separado):
```powershell
# 1. Auditoria de licencias libres (Valkey 8, Grafana OSS, versiones fijas) y SBOM SPDX:
powershell -ExecutionPolicy Bypass -File .\scripts\1_auditoria_licencias_sbom.ps1

# 2. Experimento Controlado A/B de QoS (FIFO sin colas vs tc HTB Clase 1:10 EF=46 + nftables):
docker compose exec asterisk sh /opt/openpulse/scripts/qos_experimento_ab.sh eth0

# 3. Ciberseguridad y Hacking Etico Antes vs Despues (SIP-TLS :5061 + bloqueo de fuerza bruta en nftables):
docker compose exec asterisk sh /opt/openpulse/scripts/hardening_security.sh

# 4. Reporte completo de los 15/15 indicadores del SLA:
python .\scripts\2_mediciones_completas_sla.py
```

---

## 5. Solución Rápida de Imprevistos en el Laboratorio (Plan de Contingencia)

| Imprevisto durante la demo | Causa probable | Solución en 10 segundos |
|---|---|---|
| **Nextcloud redirige a HTTPS o no deja entrar por `:8080`** | Caché del navegador o `overwriteprotocol` activo | Abrir ventana de **Incógnito** (`Ctrl+Shift+N`) y ejecutar `docker compose exec -u www-data nextcloud php occ config:system:delete overwriteprotocol`. |
| **Collabora dice "Fallo al cargar Nextcloud Office"** | Se entró por `localhost` en vez de `IP_LAB` o cambió la IP | Entrar siempre por `http://IP_LAB:8080` y, si cambió la IP, volver a correr `.\setup.ps1`. |
| **`pjsip show channelstats` devuelve `Objects found: 0`** | No hay una llamada sonando en ese segundo exacto | Ejecutar el comando **mientras** la llamada al `600` o a `1002` está conectada y en curso. |
| **Grafana muestra `No data`** | El exportador `:9105` no inició tras un reinicio | Ejecutar `docker compose exec -d asterisk python3 /opt/openpulse/scripts/sla_exporter.py` y presionar `F5` en Grafana tras 10 segundos. |
| **La laptop de 8 GB de RAM se pone lenta** | Contenedores de IA (`ollama` + `whisper`) ocupando RAM | Mantenerlos apagados durante las Demos 1–4 (`docker compose --profile ia stop ollama whisper`) y encenderlos solo para la Demo 5 (`docker compose --profile ia start ollama whisper`). |
| **Faltó escribir `docker compose` en PowerShell** | Error *"El término 'exec' no se reconoce"* | Siempre anteponer `docker compose` (ejemplo: `docker compose exec asterisk asterisk -rx "pjsip show contacts"`). |
| **El Firewall de Windows de la PC Servidor bloquea a las otras PCs del salón** | Perfil de red "Pública" en Windows | Cambiar el perfil de Wi-Fi/Ethernet a **Red Privada** en Configuración de Windows o permitir temporalmente los puertos `8080, 8443, 8081, 8444, 9980, 3000, 3001, 5070, 5061, 10000-10100`. |
