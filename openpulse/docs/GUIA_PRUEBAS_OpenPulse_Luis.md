# OpenPulse AI · Guía de pruebas en la laptop servidor (con Tailscale)

Guía de lo que hicimos el 24 de noviembre de 2026 para levantar y probar la plataforma en la laptop de Luis, con acceso desde otras redes mediante Tailscale. Todos los comandos se pegan en **PowerShell**.

> Carpeta del proyecto: `C:\Users\abdul\Desktop\TA_UNIFICADAS\OpenPulse-AI\openpulse`
> **No** usar `TA_UNIFICADAS\openpulse` (es una copia vieja de la TA1).
> IP de Tailscale de la laptop: `100.113.58.29` (IP Wi-Fi de casa: `192.168.1.15`).

---

## 0. Requisitos (una sola vez)

| Programa | Comando o descarga |
|---|---|
| Docker Desktop | `winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements` y reiniciar |
| Python | `winget install -e --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements` (luego usar `py`, no `python`) |
| Linphone | `winget install -e --id BelledonneCommunications.Linphone` o linphone.org |
| Tailscale | tailscale.com/download, iniciar sesión |

- `wsl --install` puede decir que ya existe: es normal.
- Docker Desktop con WSL 2 no muestra el control de memoria: usa la mitad de la RAM por defecto. Para limitarla, crear `%USERPROFILE%\.wslconfig` con `[wsl2]` y `memory=6GB`, y luego `wsl --shutdown`.
- Antes de cualquier comando, Docker Desktop debe decir **Engine running**.

---

## 1. Dejar el repositorio al día

```powershell
cd C:\Users\abdul\Desktop\TA_UNIFICADAS\OpenPulse-AI
Remove-Item .git\stale-*-lock-claude -ErrorAction SilentlyContinue
git checkout -- .
git pull origin main
git status
```
Debe decir `Your branch is up to date with 'origin/main'`.

> `git checkout -- .` descarta cambios locales. Si modificaste algo que quieres conservar, cópialo antes.

---

## 2. Configurar `.env` y desplegar

```powershell
cd C:\Users\abdul\Desktop\TA_UNIFICADAS\OpenPulse-AI\openpulse
copy .env.example .env
notepad .env
```
En la primera línea poner la IP con la que se van a conectar todos:
- Solo misma red (casa o hotspot): `HOST_IP=192.168.1.15` (la IPv4 de `ipconfig`).
- Desde otras redes con Tailscale: `HOST_IP=100.113.58.29`.

```powershell
docker compose config --quiet
powershell -ExecutionPolicy Bypass -File .\setup.ps1
docker compose ps
```
- `config --quiet` no debe mostrar nada.
- `setup.ps1` termina con el recuadro «ENTORNO OPENPULSE AI (TA3) LISTO».
- `ps` debe mostrar 12 servicios en **Up**.

### Arreglos que hay que aplicar después de cada `setup.ps1`

**a) Caddy no relee el Caddyfile si cambió la IP** (síntoma: `https://IP:8443` no abre):
```powershell
docker compose restart caddy
Select-String -Path caddy\Caddyfile -Pattern "https://"
```

**b) Nextcloud por HTTPS redirige a `http://...:8443`** (síntoma: «Client sent an HTTP request to an HTTPS server»). Hay que decirle que confíe en Caddy:
```powershell
docker compose exec -u www-data nextcloud php occ config:system:set trusted_proxies 0 --value="172.16.0.0/12"
docker compose exec -u www-data nextcloud php occ config:system:set forwarded_for_headers 0 --value="HTTP_X_FORWARDED_FOR"
```
Luego abrir `https://IP:8443` en una pestaña nueva (o incógnito).

**c) Video en Linphone** (Asterisk solo traía códecs de audio):
```powershell
(Get-Content asterisk\conf\pjsip.conf) -replace '^allow=ulaw,alaw,opus$','allow=ulaw,alaw,opus,vp8,h264' | Set-Content asterisk\conf\pjsip.conf -Encoding ascii
docker compose exec asterisk asterisk -rx "module reload res_pjsip.so"
docker compose exec asterisk asterisk -rx "pjsip show endpoint 1001" | Select-String "allow"
```
Debe mostrar `(ulaw|alaw|opus|vp8|h264)`.

---

## 3. Acceso desde otras redes con Tailscale

### 3.1 Firewall de Windows (PowerShell **como administrador**)
```powershell
New-NetFirewallRule -DisplayName "OpenPulse UDP" -Direction Inbound -Protocol UDP -LocalPort 3478,5070,10000-10100 -Action Allow -Profile Any
New-NetFirewallRule -DisplayName "OpenPulse TCP" -Direction Inbound -Protocol TCP -LocalPort 3000,3001,3478,5061,8080,8081,8443,8444,9443,9980 -Action Allow -Profile Any
```
Cada regla debe responder `Enabled : True`. Si dice «Acceso denegado», el PowerShell no está como administrador.

### 3.2 Compartir la laptop
Consola de Tailscale → **Machines** → `⋯` de `desktop-ujjoerl` → **Share** → enlace reusable. Mandarlo solo al chat del grupo y revocarlo después de la entrega. Los compañeros instalan Tailscale, inician sesión con su cuenta y abren el enlace.

> Compartir da acceso por red a la laptop, no control de la pantalla ni de los archivos. La laptop debe estar prendida, con Docker y Tailscale activos.

### 3.3 Certificado de Caddy (para que el navegador confíe en HTTPS)
```powershell
docker cp openpulse-caddy-1:/data/caddy/pki/authorities/local/root.crt .\caddy_root_ca.crt
```
Cada usuario: doble clic en `caddy_root_ca.crt` → **Instalar certificado** → **Usuario actual** → **Entidades de certificación raíz de confianza** → reiniciar el navegador. Sin esto, se puede entrar con **Opciones avanzadas → Continuar**.

---

## 4. Prueba del portal, SSO, chat y documentos

| Prueba | Cómo | Resultado esperado |
|---|---|---|
| Portal | `https://100.113.58.29:8443` (o `http://IP:8080`) con `admin` | Panel de Nextcloud |
| SSO + 2FA | Incógnito → «Iniciar sesión con Keycloak» → `luis.paredes` → escanear QR con FreeOTP | Entra al panel |
| Chat y presencia | `lparedes` en una ventana y `lgil` en incógnito → Talk → mensaje y estado «No molestar» | Se ve al instante en la otra cuenta |
| Documentos | Archivos → Nuevo → Documento, abrirlo en las dos ventanas | Dos cursores editando |

Credenciales por defecto (las del `.env`): usuarios Nextcloud `wantaurco`, `rpretel`, `avallejo`, `lgil`, `lparedes` y usuarios Keycloak `willian.antaurco`, `rosell.pretel`, `abdon.vallejo`, `lucia.gil`, `luis.paredes`, con `USERS_PASSWORD`; administrador con `NC_ADMIN_PASSWORD`.

> Para Collabora entrar siempre con la IP, nunca con `localhost`. Para cámara y micrófono en Talk usar HTTPS (`:8443`).

---

## 5. Prueba de llamadas con Linphone

### 5.1 Cuenta SIP (Linphone 6: «Third-party SIP account»)
| Campo | Valor (ejemplo 1001) |
|---|---|
| Username | `1001` |
| Password | `Clave1001!` (revisar con el ojo: 10 caracteres) |
| Domain | `100.113.58.29` (**sin** puerto) |
| Registrar URI | `sip:100.113.58.29:5070;transport=udp` |
| Outbound SIP Proxy URI | `sip:100.113.58.29:5070;transport=udp` |
| Transport | UDP |

Extensiones: `1001` a `1005`, clave `Clave100X!`. En la misma red usar la IP Wi-Fi en vez de la de Tailscale.

### 5.2 Comprobaciones
```powershell
docker compose exec asterisk asterisk -rx "pjsip show contacts"
docker compose exec asterisk asterisk -rx "pjsip show channelstats"
docker compose logs asterisk --tail=20
```
- `contacts`: las extensiones en **Avail** (las de otras redes con IP `100.x`).
- `channelstats` (durante la llamada): jitter y RTT en segundos, pérdida en paquetes. Sirve para RP_08 y el MOS.
- `logs`: «Failed to authenticate» indica clave incorrecta.

### 5.3 Video
Activar la cámara en Linphone (Configuración → Video), aplicar el arreglo **2.c**, hacer una llamada nueva y pulsar el ícono de cámara en los dos extremos. Para videollamadas grupales es mejor Talk.

---

## 6. Monitoreo

| Herramienta | Dirección | Notas |
|---|---|---|
| Grafana | `http://100.113.58.29:3000` → Dashboards → **OpenPulse AI – SLA** | Usuario `admin`, clave `GRAFANA_ADMIN_PASSWORD`. Rango «Last 15 minutes», refresco 10s |
| Uptime Kuma | `http://100.113.58.29:3001` | La primera vez pide crear cuenta y agregar monitores |
| Prometheus | `http://100.113.58.29:9090/targets` | Estado de la recolección |

> En `main`, los paneles de **MOS** y **% llamadas en SLA** muestran 4,39 y 100 % fijos (están escritos en el exportador). Solo el estado, la latencia y el jitter durante una llamada son reales.

---

## 7. Inteligencia artificial (Whisper + Ollama)

### 7.1 Levantar y preparar (una vez)
```powershell
docker compose --profile ia up -d --build ollama whisper
docker compose --profile ia ps ollama whisper
docker compose exec ollama ollama pull qwen2.5:0.5b
docker compose exec ollama ollama pull qwen2.5:1.5b
docker compose exec ollama ollama list
Invoke-RestMethod http://localhost:9000/health
```
Whisper debe responder `status ok, model tiny`. Si da error de conexión, esperar y revisar `docker compose logs whisper --tail=20`.

> Ollama no se instala en Windows: siempre `docker compose exec ollama ollama ...`.

### 7.2 Probar
Audio de ejemplo del repo:
```powershell
py .\scripts\3_ia_whisper_ollama_acta.py
```
Audio propio (por ejemplo, el de WhatsApp `.mp4`, `.ogg` u `.opus`, copiado a la carpeta del proyecto):
```powershell
Copy-Item "C:\ruta\al\audio.mp4" ".\prueba.mp4"
$env:OLLAMA_MODEL="qwen2.5:1.5b"
py .\scripts\3_ia_whisper_ollama_acta.py --audio ".\prueba.mp4" --salida "Acta_Prueba_Luis.md"
```
Solo texto, sin audio:
```powershell
py .\scripts\3_ia_whisper_ollama_acta.py --texto "Acuerdo 1: ... Acuerdo 2: ..." --salida "Acta_Texto.md"
```
El acta queda en la carpeta y en **Archivos** de Nextcloud de todos los usuarios.

### 7.3 Calidad
- `qwen2.5:0.5b` copia la transcripción en vez de resumir. Usar `qwen2.5:1.5b` (o `3b` con 16 GB de RAM).
- Whisper `tiny` confunde nombres («Coyabora», «Astarisk»). Para mejorar: en `docker-compose.yml`, servicio `whisper`, cambiar `WHISPER_MODEL: tiny` por `small` y ejecutar `docker compose --profile ia up -d whisper`.
- Liberar RAM al terminar: `docker compose --profile ia stop ollama whisper`.
- El script sobrescribe `Acta_Reunion_Andes_IA.md` del repo; para no subir ese cambio: `git checkout -- Acta_Reunion_Andes_IA.md`.

---

## 8. Problemas frecuentes

| Síntoma | Solución |
|---|---|
| `docker` no se reconoce | Instalar Docker Desktop y abrirlo hasta «Engine running» |
| `python` abre la Microsoft Store | Instalar Python y usar `py` |
| `https://IP:8443` no carga tras cambiar la IP | Arreglo **2.a** (`docker compose restart caddy`) |
| «Client sent an HTTP request to an HTTPS server» | Arreglo **2.b** (`trusted_proxies`) |
| «La conexión no es privada» | Normal con la CA interna; instalar el certificado (3.3) |
| Linphone «Error during connection» | Domain sin puerto, Registrar/Proxy con `:5070`, revisar la clave |
| Extensión no aparece en `contacts` | Tailscale conectado, firewall (3.1), reabrir Linphone |
| Llamada sin audio | Revisar `HOST_IP` en `.env`, volver a correr `setup.ps1`, mirar `channelstats` |
| Linphone sin video | Arreglo **2.c** y llamada nueva |
| «Fallo al cargar Nextcloud Office» | Entrar por la IP, no por `localhost` |
| Contenedor caído | `docker compose logs <servicio> --tail=30` y `docker compose restart <servicio>` |

> **Nunca** usar `docker compose down -v`: borra usuarios, documentos y Keycloak.

---

## 9. Apagar y volver a encender

```powershell
docker compose --profile ia stop          # apagar todo sin borrar datos
docker compose start                      # volver a encender la plataforma
docker compose --profile ia start ollama whisper   # encender la IA
docker compose ps
```
Si cambió la IP (otra red), actualizar `HOST_IP` en `.env`, correr `setup.ps1` y repetir los arreglos de la sección 2.
