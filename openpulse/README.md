# OpenPulse AI – Plataforma de Comunicaciones Unificadas

Proyecto del curso **TEL139 Ingeniería de Redes Unificadas (PUCP)**. Grupo **OpenPulse AI**.

Este repositorio contiene todo lo necesario para levantar, en cualquier laptop o PC del laboratorio V305, el entorno de la solución:

| Servicio | Software | URL / puerto |
|---|---|---|
| Portal, chat, videollamadas y presencia | Nextcloud Hub + Talk | `http://IP:8080` |
| Edición compartida de documentos | Collabora Online (Nextcloud Office) | `http://IP:9980` |
| Inicio de sesión único (SSO) con doble factor | Keycloak | `http://IP:8081` |
| Telefonía IP | Asterisk 20 (PJSIP) | SIP en `IP:5070/UDP`, audio en UDP 10000–10100 |
| Monitoreo de disponibilidad | Uptime Kuma | `http://localhost:3001` |
| Base de datos y caché | PostgreSQL 16 y Redis 7 | internos |

`IP` es la dirección IPv4 de la máquina donde corre Docker.

---

## 1. Requisitos

- **Docker Desktop** (Windows con WSL 2, o macOS) o **Docker Engine** (Linux).
  - En Windows con procesador Intel o AMD, descargar la versión **AMD64**, no la ARM64.
- **Git**.
- 8 GB de RAM como mínimo (16 GB recomendado). Con 8 GB, cerrar programas pesados mientras corre el entorno.
- **Linphone** en la laptop y en el celular, para las llamadas.

Comprobar Docker:
```
docker --version
docker run --rm hello-world
```

## 2. Puesta en marcha (5 pasos)

1. **Clonar el repositorio**
   ```
   git clone https://github.com/USUARIO/openpulse.git
   cd openpulse
   ```
2. **Crear el archivo `.env`** a partir de la plantilla:
   ```
   copy .env.example .env        # Windows
   cp .env.example .env          # Linux / macOS
   ```
3. **Editar `.env`**: poner en `HOST_IP` la IPv4 de tu máquina (`ipconfig` en Windows, en el adaptador Wi-Fi o Ethernet; `ip -4 addr` en Linux) y cambiar las contraseñas `cambiar`.
4. **Ejecutar el script de configuración**:
   ```
   # Windows (PowerShell, dentro de la carpeta openpulse)
   powershell -ExecutionPolicy Bypass -File .\setup.ps1

   # Linux / macOS
   bash setup.sh
   ```
   El script levanta los contenedores y configura todo automáticamente:
   - pone tu IP en la configuración de Asterisk;
   - instala Talk, Nextcloud Office y el inicio de sesión con OpenID Connect;
   - crea el grupo `openpulse` y los cinco usuarios;
   - conecta Nextcloud con Collabora;
   - crea en Keycloak el realm `openpulse`, el cliente `nextcloud` y los usuarios, con doble factor obligatorio;
   - registra Keycloak como proveedor de inicio de sesión en Nextcloud.

   Se puede ejecutar varias veces sin problema. La primera vez tarda entre 5 y 15 minutos.
5. **Completar los pasos manuales** de la sección 4.

## 3. Usuarios de prueba

Todos usan la contraseña definida en `USERS_PASSWORD` del `.env`.

| Integrante | Usuario Nextcloud | Usuario Keycloak | Extensión SIP |
|---|---|---|---|
| Willian Antaurco | `wantaurco` | `willian.antaurco` | 1001 (`Clave1001!`) |
| Rosell Pretel | `rpretel` | `rosell.pretel` | 1002 (`Clave1002!`) |
| Abdon Vallejo | `avallejo` | `abdon.vallejo` | 1003 (`Clave1003!`) |
| Lucia Gil | `lgil` | `lucia.gil` | 1004 (`Clave1004!`) |
| Luis Paredes | `lparedes` | `luis.paredes` | 1005 (`Clave1005!`) |

## 4. Pasos manuales y cómo probar cada servicio

Atajos para PowerShell (pegar al abrir cada ventana nueva):
```
function occ { docker compose exec -u www-data nextcloud php occ @args }
function ast { docker compose exec asterisk asterisk -rx "$args" }
```

### Chat, video y presencia
- Abrir `http://localhost:8080` en una ventana normal y en otra de incógnito, con dos usuarios distintos.
- En **Talk**, crear una conversación, escribir y hacer una videollamada.
- La cámara y el micrófono solo funcionan en `localhost` o con HTTPS. Para usarlos desde otra máquina por IP, en Chrome: `chrome://flags/#unsafely-treat-insecure-origin-as-secure` → agregar `http://IP:8080`.

### Documentos (Collabora)
- **Entrar a Nextcloud por `http://IP:8080`, no por `localhost`.** Si se entra por localhost aparece "Fallo al cargar Nextcloud Office".
- Crear un documento, compartirlo con el grupo `openpulse` y abrirlo con dos usuarios a la vez.

### Inicio de sesión con Keycloak
- Sin HTTPS, Nextcloud bloquea el inicio con OpenID Connect ("You must access Nextcloud with HTTPS"). Solo para probar:
  ```
  occ config:system:set debug --value=true --type=boolean
  ```
  Probar en incógnito con **"Iniciar sesión con Keycloak"** (la primera vez pide configurar el doble factor con Google Authenticator) y luego **desactivar**:
  ```
  occ config:system:set debug --value=false --type=boolean
  ```

### Llamadas (Asterisk + Linphone)
- En Linphone: **Usar una cuenta SIP** → usuario `1001`, dominio `IP:5070`, contraseña `Clave1001!`, transporte **UDP**.
- En los ajustes de audio de Linphone, el códec **PCMU** debe estar activo (Asterisk solo acepta G.711).
- Comprobar el registro: `ast pjsip show contacts` (debe decir `Avail`).
- Llamar a otra extensión o al **600** (prueba de eco).
- Durante la llamada, ver jitter, pérdida y RTT: `ast pjsip show channelstats`.
- En el celular, dejar Linphone abierto en primer plano para recibir llamadas.

### Monitoreo (Uptime Kuma)
- Abrir `http://localhost:3001` y crear la cuenta.
- Agregar monitores **HTTP(s)** cada 60 s:
  - `http://IP:8080/status.php`
  - `http://IP:9980/hosting/discovery`
  - `http://IP:8081/realms/openpulse`
- Para Asterisk: **Settings → Docker Hosts** → Socket `/var/run/docker.sock`; luego un monitor **Docker Container** con el nombre `openpulse-asterisk-1`.
- Crear una **página de estado** con todos los monitores.

## 5. Problemas conocidos y su solución

| Síntoma | Causa | Solución |
|---|---|---|
| `ports are not available ... 5060` al levantar Asterisk | Linphone u otro programa ocupa el puerto 5060 de la máquina | Por eso Asterisk se publica en el **5070**. Usar `IP:5070` en Linphone |
| La llamada conecta pero no hay audio | Docker hace que los teléfonos parezcan venir de `172.18.0.1` | `pjsip.conf` **no** debe tener `local_net=172.16.0.0/12` (ya está corregido) |
| Tras reiniciar Asterisk, los teléfonos aparecen `Unavail` | Docker pierde la ruta de regreso a los teléfonos | Cerrar y volver a abrir Linphone en cada equipo |
| "El anfitrión WOPI no está autorizado" | La URL de retorno de Collabora quedó en automático | `occ richdocuments:activate-config --wopi-url="http://IP:9980" --callback-url="http://IP:8080"` |
| "Fallo al cargar Nextcloud Office (Collabora)" | Se entró a Nextcloud por `localhost` | Entrar por `http://IP:8080` |
| "You must access Nextcloud with HTTPS to use OpenID Connect" | No hay HTTPS en esta etapa | Modo depuración solo para la prueba (sección 4); en la TA2 se agrega HTTPS |
| Monitores de Uptime Kuma en rojo con `ECONNREFUSED` | URL con otra IP o con `https` | Usar `http://` y la IP real de la máquina |
| "Acceso a través de un dominio no confiable" | La IP cambió | Actualizar `HOST_IP` en `.env` y volver a ejecutar el script de configuración |
| Docker Desktop: "No se puede ejecutar esta aplicación en el equipo" | Se descargó el instalador ARM64 en una PC Intel o AMD | Descargar la versión AMD64 |

**Si cambia la IP** (otra red Wi-Fi, otra PC): editar `HOST_IP` en `.env` y volver a ejecutar el script de configuración. Luego reconfigurar Linphone y los monitores con la nueva IP.

## 6. Comandos útiles

```
docker compose ps                 # estado de los contenedores
docker compose logs -f nextcloud  # registros de un servicio
docker compose stop               # detener sin borrar datos
docker compose start              # volver a iniciar
docker compose restart asterisk   # reiniciar un servicio
```

> **No usar `docker compose down -v`**: borra todos los datos (usuarios, documentos, configuración de Keycloak y de Uptime Kuma).

## 7. Cómo trabajar en equipo

- Cada integrante trabaja en una **rama de su frente** y la une a `main` cuando está probada:

  | Frente | Responsable | Rama |
  |---|---|---|
  | Coordinación, integración y SSO | W. Antaurco | `sso-integracion` |
  | Voz y telefonía IP | R. Pretel | `voz` |
  | Video, chat y presencia | A. Vallejo | `video-chat` |
  | Documentos e IA | L. Gil | `docs-ia` |
  | Red, QoS, ciberseguridad y monitoreo | L. Paredes | `red-seguridad` |

  ```
  git checkout -b voz
  # ... cambios ...
  git add .
  git commit -m "Voz: SRTP en las extensiones"
  git push -u origin voz
  ```
- **Nunca subir el `.env`**: el `.gitignore` ya lo excluye. Revisar con `git status` antes de cada commit.
- Toda configuración nueva debe quedar en archivos del repositorio o en el script de configuración, para que se reproduzca en el V305.

## 8. Pendientes para la TA2 (16 de noviembre)

| Tarea | Responsable |
|---|---|
| Levantar el entorno en el **V305** y anotar el hardware de las PC | Todo el equipo |
| **HTTPS** en todo el entorno: proxy inverso (Caddy o Nginx) con certificados de una CA interna (mkcert); retirar el modo depuración | W. Antaurco |
| **OpenLDAP** como directorio de Keycloak | W. Antaurco |
| **Cifrado de la voz:** SIP sobre TLS y SRTP en Linphone; softphone web por WebRTC (WSS y DTLS-SRTP) | R. Pretel |
| Llamadas de prueba automatizadas con **SIPp** y estimación del **MOS** | R. Pretel |
| **coturn** (TURN/STUN) y **Jitsi Meet** como SFU para reuniones grandes | A. Vallejo |
| Medición de tiempos de entrega de mensajes y de cambio de presencia | A. Vallejo |
| **Whisper + Ollama** para la transcripción y el resumen de reuniones | L. Gil |
| **QoS:** marcado DSCP (EF voz, AF41 video, CS5 señalización) y colas con `nftables` y `tc`; verificación con Wireshark | L. Paredes |
| **Prometheus + Grafana** con los indicadores del SLA; **fail2ban** y **Wazuh** | L. Paredes |
| Redacción del **SLA**: indicadores, tiempos de respuesta, penalidades y exclusiones | Todo el equipo |

Mediciones de la TA1 que sirven como línea base (llamada G.711 laptop–celular): jitter de 1 a 4 ms, RTT de 9 a 12 ms, pérdida de 0 % en la laptop y de 1,9 % en el celular.
