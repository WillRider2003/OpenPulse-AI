# TA3 · Abdon · Video, chat y presencia

Hola Abdon. Esta es tu guía para la TA3. Sigue el orden. Toda captura debe mostrar la fecha: ejecuta `Get-Date` antes del comando. **Entrega el 24 de noviembre** en `TA3/capturas/Abdon` de Drive, más tu texto en el documento compartido.

Tu objetivo: medir lo que en la TA2 quedó como «meta de diseño» (tiempo de entrega del chat y cambio de presencia) y mostrar la videollamada entre redes distintas.

---

## 1. Levantar el entorno (captura AV_01)

```
Get-Date
docker compose ps
```
**Captura:** `TA3_AV_01_contenedores.png`

---

## 2. Tiempo de entrega del chat (captura AV_02)

La meta del SLA es que un mensaje llegue en menos de 2 segundos (percentil 95).

**Opción simple (manual):** con dos usuarios abiertos (ventana normal e incógnito), uno envía 20 mensajes y con un cronómetro mides cuánto tardan en aparecer en la otra. Anota los 20 tiempos en una tabla.

**Opción con script (recomendada):** te paso `medir_chat.ps1`. Lo ejecutas así (necesitas el token de una conversación de Talk y una contraseña de aplicación de Nextcloud):
```
Get-Date
.\medir_chat.ps1 -IP TU_IP -Usuario avallejo -Clave CONTRASEÑA_APP -Token TOKEN_SALA -Veces 20
```
El script envía 20 mensajes, mide cuánto tarda cada uno en estar disponible y calcula el promedio, el máximo y el percentil 95.
**Captura:** `TA3_AV_02_tiempo-chat.png` (la salida con los tiempos y el percentil 95)

> El token de la sala es la última parte de la URL de la conversación en Talk. La contraseña de aplicación se crea en Nextcloud → Configuración → Seguridad → Crear nueva contraseña de aplicación.

---

## 3. Tiempo de cambio de presencia (captura AV_03)

La meta del SLA es que el estado se actualice en menos de 5 segundos.

Con dos cuentas abiertas: una cambia su estado (En línea → Ausente → No molestar) y con un cronómetro mides cuánto tarda en verse el cambio en la otra cuenta. Hazlo 10 veces y anota el promedio y el máximo.
**Captura:** `TA3_AV_03_tiempo-presencia.png` (tu tabla de tiempos, con la pantalla de los dos estados)

---

## 4. Videollamada de 3 personas con estadísticas (capturas AV_04, AV_05)

1. Inicia una videollamada en Talk con **tres participantes** (pueden ser tres pestañas con usuarios distintos, o compañeros).
**Captura:** `TA3_AV_04_videollamada-3.png`

2. En **Firefox**, mientras la llamada está activa, abre en otra pestaña:
```
about:webrtc
```
Busca la sección de estadísticas RTP y anota: **resolución**, **fotogramas por segundo (fps)** y **paquetes perdidos**.
**Captura:** `TA3_AV_05_estadisticas-webrtc.png`

Meta del SLA: 720p a 25 fps o más, pérdida ≤ 1 %.

---

## 5. coturn: llamadas entre redes distintas (capturas AV_06, AV_07)

coturn (servidor TURN) permite que la videollamada funcione cuando los usuarios están en redes diferentes (por ejemplo, uno en Wi-Fi y otro con datos móviles).

1. Agrega coturn a `docker-compose.yml` (antes de `volumes:` del final):
```yaml
  coturn:
    image: coturn/coturn:4.6
    network_mode: host
    command: >
      -n --realm=openpulse --server-name=openpulse
      --lt-cred-mech --user=openpulse:openpulse2026
      --min-port=49160 --max-port=49200 --no-tls --no-dtls
    restart: unless-stopped
```

2. En Nextcloud, como admin: Configuración → Talk → **servidores TURN**:
   - Servidor: `TU_IP:3478`
   - Usuario: `openpulse`, contraseña: `openpulse2026`
   - Protocolos: UDP y TCP
**Captura:** `TA3_AV_06_coturn-config.png`

3. Haz una videollamada entre tu laptop (Wi-Fi) y tu celular **con datos móviles** (no Wi-Fi). Debe conectar y verse el video.
**Captura:** `TA3_AV_07_videollamada-redes.png`

> Si no logras coturn a tiempo, no es bloqueante: déjalo como «planificado» y avisa al grupo. Lo importante son las mediciones de chat y presencia.

---

## 6. Compartir pantalla y archivo (capturas AV_08, AV_09)

Son funciones que usaría la MYPE en sus reuniones.
1. En una videollamada, comparte tu pantalla.
**Captura:** `TA3_AV_08_pantalla-compartida.png`
2. En el chat, envía un archivo y ábrelo desde la otra cuenta.
**Captura:** `TA3_AV_09_archivo-chat.png`

---

## 7. Texto para el informe (sección «Video, chat y presencia»)

De 1 a 1,5 páginas, tercera persona, tono técnico:
- Mediciones de chat y presencia frente a las metas del SLA (tabla).
- Resultados de la videollamada de 3 personas (resolución, fps, pérdida).
- coturn y su utilidad para la MYPE (llamadas entre redes).
- Conclusión breve.

---

## Resumen de capturas

| Nombre | Qué muestra |
|---|---|
| TA3_AV_01_contenedores | Entorno levantado |
| TA3_AV_02_tiempo-chat | Tiempos de entrega del chat y percentil 95 |
| TA3_AV_03_tiempo-presencia | Tiempos de cambio de presencia |
| TA3_AV_04_videollamada-3 | Videollamada de 3 personas |
| TA3_AV_05_estadisticas-webrtc | Estadísticas WebRTC (resolución, fps, pérdida) |
| TA3_AV_06_coturn-config | coturn configurado en Talk |
| TA3_AV_07_videollamada-redes | Videollamada entre Wi-Fi y datos móviles |
| TA3_AV_08_pantalla-compartida | Pantalla compartida |
| TA3_AV_09_archivo-chat | Archivo enviado por el chat |

Cualquier duda, escribe al grupo con la captura del error. ¡Gracias!
