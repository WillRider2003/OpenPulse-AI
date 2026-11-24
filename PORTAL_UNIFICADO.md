# OpenPulse AI · Portal de Comunicaciones Unificadas

**TEL139 · Ingeniería de Redes Unificadas · PUCP**  
**Espacio de trabajo del Estudio Contable Andes & Asociados**

## Qué conecta el portal

| Servicio | Flujo en Spring Web | Servicio que lo ejecuta |
|---|---|---|
| Voz y telefonía | Directorio de extensiones, botón de apertura del cliente y prueba de eco 600 | Asterisk y Linphone Desktop por SIP-TLS |
| Video y chat persistente | Conversaciones, mensajes de texto y acceso a la videollamada de cada sala | Nextcloud Talk y la configuración WebRTC del stack |
| Presencia | Disponibilidad publicada para cada integrante del directorio | Nextcloud User Status |
| Archivos y coedición | Navegar, subir, descargar y abrir documentos compatibles con Office | Nextcloud Files, WebDAV y Collabora |
| Asistente y actas | Importar audio de Linphone, transcribir, revisar el borrador, guardarlo y compartirlo con una sala | Whisper, Ollama o Gemini, Nextcloud Files y Talk |
| Operación | Comprobaciones actuales y accesos a consolas web | Spring Web, Grafana, Prometheus, Nextcloud y Keycloak |

La web entrega su interfaz y API desde un único servidor Java. Las consultas a
Nextcloud usan Login Flow v2 y una credencial de aplicación por usuario, guardada
en la sesión de Spring. Nextcloud conserva sus permisos, su SSO con Keycloak si
ya está configurado, y los historiales de archivos y salas. El directorio conoce
las extensiones del proyecto y sus alias de usuario Nextcloud y Keycloak.

La prueba SIP del tablero comprueba el puerto TCP. El registro, la negociación
TLS/SRTP y la calidad del audio se verifican en Linphone, Asterisk y Grafana
durante una llamada. Las señales de disponibilidad del portal corresponden a la
consulta actual. El SLA requiere las mediciones reales de cada servicio.

## Puesta en marcha en V305

1. Desde `openpulse/`, configura el `.env` existente. Para una instalación
   nueva, copia `.env.example`, completa las contraseñas y establece `HOST_IP`
   con la IPv4 del servidor V305. Ejecuta `setup.ps1` en Windows o `bash setup.sh`
   en Linux/macOS para aprovisionar el stack base.
2. Arranca el portal y aplica la configuración del proxy.

   ```sh
   docker compose --profile portal up -d --build portal
   docker compose up -d caddy
   docker compose restart caddy
   ```

3. Abre `https://IP_DEL_SERVIDOR:8445` desde los equipos de la LAN. Instala en
   los clientes la CA del Caddy de este stack según la guía V305. Si el dominio
   visible de Nextcloud, el de Keycloak o el SIP del laboratorio son distintos,
   ajusta `NEXTCLOUD_PUBLIC_URL`, `KEYCLOAK_PUBLIC_URL` y `SIP_DOMAIN` en `.env`
   y recrea el servicio portal. La URL pública de Nextcloud debe figurar entre
   sus dominios de confianza.
4. En **Conectar cuenta**, prepara la conexión y presiona **Autorizar en
   Nextcloud**. Completa el formulario de Nextcloud o su SSO, autoriza
   OpenPulse Portal y vuelve a la primera pestaña. La conexión se actualiza
   automáticamente. Para desvincular el portal, cierra su sesión. También
   puedes revocar OpenPulse desde **Ajustes personales → Seguridad** de Nextcloud.

Si actualizas un stack ya aprovisionado con Collabora por HTTP, aplica una vez
esta configuración de Office después de recrear los servicios. Sustituye
`IP_DEL_SERVIDOR` por el valor de `HOST_IP`.

```sh
docker compose exec -u www-data nextcloud php occ richdocuments:activate-config --wopi-url=http://collabora:9980 --callback-url=http://nextcloud:80
docker compose exec -u www-data nextcloud php occ config:app:set richdocuments public_wopi_url --value=https://IP_DEL_SERVIDOR:9443
```

Compose usa una red interna dedicada entre Caddy y Nextcloud. Si la subred
`172.31.245.0/28` ya está ocupada, define otra en `OPENPULSE_PROXY_SUBNET` y
la última IP utilizable de esa red en `OPENPULSE_PROXY_IP`. Nextcloud confía únicamente
en la IP que corresponde a Caddy para reconocer el protocolo HTTPS.
[Proxy inverso de Nextcloud](https://docs.nextcloud.com/server/stable/admin_manual/configuration_server/reverse_proxy_configuration.html)

Para un dominio distinto de Office, configura `COLLABORA_PUBLIC_HOST` con
el host y puerto externos y usa el mismo origen HTTPS en `public_wopi_url`.

La administración usa las consolas de Nextcloud y Keycloak con sus respectivas
cuentas autorizadas. El stack de laboratorio debe permanecer accesible
únicamente desde la red de práctica o una VPN.

### Ejecutar el portal desde Java o IntelliJ

Abre el proyecto Maven `openpulse/portal/pom.xml` con **JDK 21** y ejecuta
`PortalApplication`, o ejecuta desde `openpulse/portal/`:

```sh
mvn spring-boot:run
```

Abre `http://localhost:8092`. Sin variables, el portal busca Nextcloud
en `http://localhost:8080` y SIP-TLS en `localhost:5061`. Define
`NEXTCLOUD_INTERNAL_URL` para el acceso de Spring, `NEXTCLOUD_PUBLIC_URL`
para el acceso del navegador y `SIP_DOMAIN` para Linphone si tus servicios
corren en otra máquina. Para una instalación que solo use HTTPS en los
servicios remotos, configura el almacén de confianza Java con la CA del
laboratorio. El servidor Java escucha en loopback por defecto.

## Asistente y reunión a acta

Activa los servicios locales y descarga el modelo una sola vez:

```sh
docker compose --profile ia up -d whisper ollama
docker compose exec ollama ollama pull qwen2.5:0.5b
```

En el portal ya conectado:

1. Abre **Telefonía** y llama a otra extensión en Linphone. Prueba el eco en
   **600**. En Linphone Desktop registra primero tu extensión en Asterisk
   con TLS **5061**, la clave SIP de tu `.env` y la confianza del certificado
   de Asterisk del laboratorio. El vínculo se entrega al manejador
   `sip-linphone:` del sistema.
2. Con consentimiento de quienes participan, graba la reunión en Linphone.
   En **Asistente IA → Reunión a acta**, selecciona la grabación exportada.
   Whisper transcribe en local. También puedes pegar las notas de la reunión.
3. Genera un borrador, corrige compromisos y fechas, y guárdalo. El acta se
   escribe en **Mi unidad** o en la última carpeta abierta del portal.
4. Elige una sala y presiona **Compartir acta**. Talk recibe el archivo con
   los permisos del servidor. Puedes volver a Nube privada para abrirlo o
   descargarlo.

**Gemini es opcional.** Configura en el `.env` del servidor
`GEMINI_API_KEYS=clave1,clave2`, sin espacios, y por defecto
`GEMINI_MODEL=gemini-3.1-flash-lite`. Para una sola clave también existe
`GEMINI_API_KEY`. Recrea el portal con
`docker compose --profile portal up -d --force-recreate portal`.

El servidor alterna claves habilitadas, difiere las que reciben 429 y permite
hasta tres intentos elegibles en una consulta. Las claves se quedan en el
servidor. Las cuotas de Google se aplican al proyecto. El motor local es el
predeterminado y mantiene la ruta de software libre de la TA. Solo al
seleccionar Gemini y confirmar el envío se transmiten el texto de la consulta
y el historial correspondiente. La grabación siempre se procesa en Whisper.
[API de Gemini](https://ai.google.dev/api/generate-content) ·
[Cuotas de Gemini](https://ai.google.dev/gemini-api/docs/rate-limits)

## Recorrido para la demostración

- **Voz.** En dos equipos, registra dos extensiones. Llama desde el directorio,
  comprueba audio en ambos sentidos y prueba la extensión 600.
- **Chat, video y presencia.** Conecta dos cuentas. Abre un chat directo desde
  el directorio, manda un mensaje en el portal y comprueba que aparece en Talk.
  Publica un estado en Nextcloud y actualiza el directorio. Usa la misma sala
  para iniciar una videollamada en Talk.
- **Documentos.** Sube un documento de prueba a una carpeta compartida, ábrelo
  con Nextcloud Office y edítalo en simultáneo desde los dos equipos.
- **IA.** Importa el audio de una llamada de prueba, guarda el borrador
  revisado y comparte el acta en la sala. Usa Ollama para el flujo local.
- **SLA.** Abre Operación y SLA, consulta Grafana y captura las métricas
  obtenidas durante la prueba en V305. El informe final y el video de PAIDEIA
  pertenecen a la entrega académica del equipo.

[Login Flow de Nextcloud](https://docs.nextcloud.com/server/stable/developer_manual/client_apis/LoginFlow/index.html) ·
[WebDAV de Nextcloud](https://docs.nextcloud.com/server/stable/developer_manual/client_apis/WebDAV/basic.html) ·
[API de Talk](https://nextcloud-talk.readthedocs.io/en/stable/chat/) ·
[Manejadores URI de Linphone Desktop](https://wiki.linphone.org/xwiki/wiki/public/view/Linphone/URI%20Handlers%20%28Desktop%20only%29/)
