# TA3 · Luis · Ciberseguridad, QoS y monitoreo

Hola Luis. Tu sección es nueva y obligatoria en la TA3, y es la más vistosa para el video. Sigue el orden. Toda captura debe mostrar la fecha: ejecuta `Get-Date` antes del comando. **Entrega el 24 de noviembre** en `TA3/capturas/Luis` de Drive, más tu texto en el documento compartido.

> ⚠️ **MUY IMPORTANTE:** todos los escaneos y ataques se hacen **solo contra tu propia laptop**, en tu casa o con el hotspot de tu celular. **NUNCA en la red de la PUCP.** Escanear equipos ajenos puede violar las normas de la universidad y la ley. Tú atacas tu propio servidor para demostrar que sabes defenderlo.

---

## 1. Levantar el entorno (captura LP_01)

```
Get-Date
docker compose ps
```
Anota tu IP con `ipconfig` (la IPv4 de tu Wi-Fi). En esta guía la llamo `TU_IP`.
**Captura:** `TA3_LP_01_contenedores.png`

---

## 2. Escaneo inicial con nmap (capturas LP_02, LP_03)

Instala nmap desde https://nmap.org/download.html (versión para Windows).

1. Escaneo de puertos TCP y servicios:
```
Get-Date
nmap -sV -p- TU_IP
```
**Captura:** `TA3_LP_02_nmap-inicial.png`

2. Escaneo de los puertos SIP (UDP):
```
nmap -sU -p 5060,5061 TU_IP
```
**Captura:** `TA3_LP_03_nmap-sip.png`

Anota qué puertos están abiertos: te servirán para comparar después del endurecimiento.

---

## 3. Ataque SIP controlado con SIPVicious (capturas LP_04, LP_05, LP_06)

SIPVicious simula cómo un atacante busca centralitas y adivina contraseñas. Lo corres desde un contenedor para no instalar nada:

1. Descubrir el servicio SIP (`svmap`):
```
Get-Date
docker run --rm --network host sipvicious/sipvicious svmap TU_IP:5060
```
**Captura:** `TA3_LP_04_svmap.png`

2. Enumerar extensiones (`svwar`):
```
docker run --rm --network host sipvicious/sipvicious svwar -e 1000-1010 TU_IP:5060
```
**Captura:** `TA3_LP_05_svwar.png` (debería descubrir las extensiones 1001–1005)

3. Intentar adivinar la contraseña de una extensión (`svcrack`):
```
docker run --rm --network host sipvicious/sipvicious svcrack -u 1001 -r 1000-9999 TU_IP:5060
```
**Captura:** `TA3_LP_06_svcrack.png`

Esto demuestra la amenaza: sin protección, un atacante enumera extensiones e intenta claves por fuerza bruta.

---

## 4. Endurecimiento: fail2ban y nftables (capturas LP_07, LP_08)

**fail2ban** bloquea una IP que falle demasiados registros SIP.

1. Agrega fail2ban a `docker-compose.yml` (antes de `volumes:` del final):
```yaml
  fail2ban:
    image: crazymax/fail2ban:latest
    network_mode: host
    cap_add: [NET_ADMIN, NET_RAW]
    volumes:
      - ./fail2ban:/data
      - ./asterisk/logs:/var/log/asterisk:ro
    restart: unless-stopped
```

2. Crea la carpeta `fail2ban/jail.d/` y dentro un archivo `asterisk.conf`:
```
[asterisk]
enabled = true
port = 5060,5061
filter = asterisk
logpath = /var/log/asterisk/messages
maxretry = 3
bantime = 600
findtime = 60
```
(En Asterisk, activa el registro de seguridad en `logger.conf`: una línea `messages => security,notice,warning,error`.)

3. Levanta fail2ban:
```
docker compose up -d fail2ban
Get-Date
docker compose exec fail2ban fail2ban-client status asterisk
```
**Captura:** `TA3_LP_07_fail2ban-status.png`

4. **nftables:** muestra las reglas de firewall que dejan abiertos solo los puertos necesarios (8080, 8081, 9980, 5060, 5061, 3478). Si no alcanzas a configurar nftables completo, al menos documenta la tabla de puertos que deberían estar abiertos y cerrados.
**Captura:** `TA3_LP_08_firewall.png`

---

## 5. Repetir el ataque: antes y después (capturas LP_09, LP_10)

Esta es la evidencia estrella: el ataque funcionaba y ahora se bloquea.

1. Vuelve a lanzar `svwar` o `svcrack` (paso 3). Tras 3 intentos fallidos, fail2ban debe bloquear tu IP de prueba.
```
Get-Date
docker compose exec fail2ban fail2ban-client status asterisk
```
Debe mostrar la IP en «Banned IP list».
**Captura:** `TA3_LP_09_fail2ban-bloqueo.png`

2. Vuelve a correr nmap y compara: deberían verse menos puertos expuestos que en el paso 2.
**Captura:** `TA3_LP_10_nmap-despues.png`

---

## 6. Prueba de QoS controlada (capturas LP_11 a LP_15)

Dos llamadas **iguales** con la misma carga de red, una sin prioridad y otra con cola prioritaria para la voz (DSCP EF). Así se demuestra el efecto real de la QoS.

**Preparación (una sola vez):**
```
docker run -d --name iperf-srv --network openpulse_default networkstatic/iperf3 -s
function tcq { docker run --rm --network container:openpulse-asterisk-1 --cap-add NET_ADMIN alpine sh -c "apk add -q iproute2 && $args" }
```

**Escenario A — sin prioridad (FIFO):**
```
tcq "tc qdisc replace dev eth0 root tbf rate 2mbit burst 32kbit latency 50ms"
```
- Llama de la 1001 a la 1002, espera 30 s.
- `Get-Date` y `docker compose exec asterisk asterisk -rx "pjsip show channelstats"` → **captura LP_11**
- Lanza carga 2 min: `docker run --rm --network container:openpulse-asterisk-1 networkstatic/iperf3 -c iperf-srv -t 120 -P 4`
- Al terminar: `channelstats` de nuevo → **captura LP_12**. Cuelga.

**Escenario B — con prioridad para la voz (EF):**
```
tcq "tc qdisc del dev eth0 root; tc qdisc add dev eth0 root handle 1: htb default 20; tc class add dev eth0 parent 1: classid 1:1 htb rate 2mbit; tc class add dev eth0 parent 1:1 classid 1:10 htb rate 300kbit ceil 2mbit prio 0; tc class add dev eth0 parent 1:1 classid 1:20 htb rate 1700kbit ceil 2mbit prio 1; tc filter add dev eth0 parent 1: protocol ip u32 match ip dsfield 0xb8 0xfc flowid 1:10"
```
- Llamada **nueva** 1001→1002, y repite lo mismo: `channelstats` antes de la carga → **captura LP_13**, y después de la carga → **captura LP_14**.
- Antes de colgar, la prueba de que la voz pasó por la cola prioritaria (la clase 1:10 debe tener paquetes):
```
tcq "tc -s class show dev eth0"
```
**Captura:** `TA3_LP_15_tc-class.png`

**Limpieza:**
```
tcq "tc qdisc del dev eth0 root"
```

Resultado esperado: en el escenario B, la pérdida de la voz baja frente al escenario A.

---

## 7. Corregir Grafana y agregar monitores (capturas LP_16, LP_17)

1. En Grafana, corrige el panel de estado para que «activo» salga en verde y no en rojo (cambia el umbral de color en el panel).
**Captura:** `TA3_LP_16_grafana.png`

2. En Uptime Kuma, agrega monitores sobre HTTPS (el portal en el puerto 8443) y sobre los puertos publicados.
**Captura:** `TA3_LP_17_monitores.png`

---

## 8. Texto para el informe (sección «Ciberseguridad y hacking ético»)

Unas 2 páginas, tercera persona, tono técnico:
- Amenazas de la Lección 09 (sniffing, spoofing, man-in-the-middle, DoS) aplicadas a la plataforma.
- El ataque realizado (nmap + SIPVicious) y qué encontró.
- Las medidas: SIP sobre TLS/SRTP, HTTPS, doble factor, fail2ban, nftables.
- La comparación antes/después (tabla).
- La prueba de QoS y su resultado.
- Conclusión breve.

---

## Resumen de capturas

| Nombre | Qué muestra |
|---|---|
| TA3_LP_01_contenedores | Entorno levantado |
| TA3_LP_02_nmap-inicial | Puertos y servicios antes |
| TA3_LP_03_nmap-sip | Puertos SIP |
| TA3_LP_04_svmap | SIPVicious descubre el servicio |
| TA3_LP_05_svwar | Enumeración de extensiones |
| TA3_LP_06_svcrack | Intento de adivinar clave |
| TA3_LP_07_fail2ban-status | fail2ban activo |
| TA3_LP_08_firewall | Reglas de firewall |
| TA3_LP_09_fail2ban-bloqueo | fail2ban bloquea la IP atacante |
| TA3_LP_10_nmap-despues | Menos puertos expuestos |
| TA3_LP_11 a 14_channelstats | QoS: antes y después, A y B |
| TA3_LP_15_tc-class | Voz en la cola prioritaria |
| TA3_LP_16_grafana | Tablero corregido |
| TA3_LP_17_monitores | Monitores HTTPS |

Cualquier duda, escribe al grupo con la captura del error. ¡Gracias!
