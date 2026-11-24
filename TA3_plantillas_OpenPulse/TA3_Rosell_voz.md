# TA3 · Rosell · Voz y telefonía IP

Hola Rosell. Esta es tu guía paso a paso para la TA3. Sigue el orden. Toda captura debe mostrar la fecha: ejecuta `Get-Date` antes del comando. Guarda cada captura con el nombre que te indico.

**Entrega todo el 24 de noviembre** en la carpeta `TA3/capturas/Rosell` de Drive, más tu texto en el documento compartido.

---

## 1. Levantar el entorno (captura RP_01)

```
Get-Date
docker compose ps
```
Si no están en «Up», ejecuta `docker compose up -d` y espera 2 minutos.
**Captura:** `TA3_RP_01_contenedores.png`

---

## 2. SIP sobre TLS (capturas RP_02, RP_03, RP_04)

El objetivo es que la señalización SIP viaje cifrada, no solo el audio.

1. Genera un certificado para Asterisk (en la carpeta `openpulse`):
```
docker compose exec asterisk sh -c "cd /etc/asterisk/keys && openssl req -new -x509 -days 365 -nodes -newkey rsa:2048 -keyout asterisk.key -out asterisk.crt -subj '/CN=openpulse'"
```
Si la carpeta `keys` no existe: `docker compose exec asterisk mkdir -p /etc/asterisk/keys` y repite.

2. En `asterisk/conf/pjsip.conf`, agrega al inicio un transporte TLS:
```
[transport-tls]
type=transport
protocol=tls
bind=0.0.0.0:5061
cert_file=/etc/asterisk/keys/asterisk.crt
priv_key_file=/etc/asterisk/keys/asterisk.key
method=tlsv1_2
```
Y en cada extensión que uses para la prueba, asegúrate de tener `media_encryption=sdes`.

3. Publica el puerto 5061 en `docker-compose.yml`, en el servicio `asterisk`, dentro de `ports:`:
```
      - "5061:5061/tcp"
```

4. Reinicia Asterisk:
```
docker compose up -d
docker compose restart asterisk
```

5. Verifica el transporte TLS:
```
Get-Date
docker compose exec asterisk asterisk -rx "pjsip show transports"
```
**Captura:** `TA3_RP_02_transporte-tls.png` (debe aparecer el transporte en el puerto 5061, protocolo tls)

6. En **Linphone**, edita la cuenta SIP:
   - Transporte: **TLS**
   - Dominio y servidor: `TU_IP:5061`
   - En Preferencias → Red, activa **cifrado de medios: SRTP**.
   Vuelve a registrar la cuenta.
**Captura:** `TA3_RP_03_linphone-tls.png` (cuenta registrada, «Conectado», por TLS)

7. Haz una llamada entre dos extensiones. Linphone debe mostrar el candado y «Point-to-point encrypted call».
**Captura:** `TA3_RP_04_llamada-cifrada.png`

---

## 3. Comparación antes/después en Wireshark (capturas RP_05, RP_06)

Esto demuestra que antes la señalización se leía y ahora no.

1. Abre **Wireshark**, elige la interfaz por la que te conectas (Wi-Fi o Ethernet) y usa el filtro:
```
sip || tls
```
2. Haz una llamada **por UDP** (puerto 5060, sin TLS) y detén la captura. Verás los mensajes SIP (INVITE, con usuarios y extensiones legibles).
**Captura:** `TA3_RP_05_sip-sin-cifrar.png`

3. Haz otra llamada **por TLS** (puerto 5061) y detén la captura. El contenido aparece como «Application Data» cifrado, ilegible.
**Captura:** `TA3_RP_06_sip-cifrado-tls.png`

---

## 4. Llamadas de prueba con SIPp (capturas RP_07, RP_08)

SIPp genera llamadas automáticas y nos da estadísticas reales para el SLA.

1. Descarga SIPp para Windows (o úsalo desde un contenedor). Forma más simple, con contenedor:
```
Get-Date
docker run --rm -it --network openpulse_default ctaloi/sipp -sn uac -d 60000 -s 600 TU_IP:5060 -m 10 -r 1 -trace_stat -stf stats.csv
```
   - `-s 600` llama a la extensión de eco 600.
   - `-m 10` hace 10 llamadas, `-d 60000` cada una dura 60 s.
**Captura:** `TA3_RP_07_sipp-resumen.png` (al final muestra «Successful call» y «Failed call»)

2. Durante la prueba, en otra ventana, mira las estadísticas de la llamada:
```
docker compose exec asterisk asterisk -rx "pjsip show channelstats"
```
**Captura:** `TA3_RP_08_channelstats.png`

---

## 5. Cálculo del MOS

El MOS (Mean Opinion Score) estima la calidad de la voz del 1 (mala) al 5 (excelente). Usa el modelo E simplificado. Para cada llamada, toma de las estadísticas: **latencia de ida y vuelta (RTT)**, **jitter** y **pérdida (%)**.

Fórmula (modelo E simplificado):

1. Retardo efectivo: `Ef = (RTT / 2) + (2 × jitter) + 10`   (todo en milisegundos)
2. Factor R:
   - Si `Ef < 160`:  `R = 93.2 − (Ef / 40) − (2.5 × perdida)`
   - Si `Ef ≥ 160`:  `R = 93.2 − ((Ef − 120) / 10) − (2.5 × perdida)`
   (perdida en %, por ejemplo 1.9)
3. MOS: `MOS = 1 + 0.035 × R + 7e−6 × R × (R − 60) × (100 − R)`

Interpretación: MOS ≥ 4.0 es muy bueno (la meta del SLA). Entre 3.5 y 4.0 es aceptable.

Tienes una hoja de cálculo lista (`calculo_mos.xlsx`): escribes RTT, jitter y pérdida de cada llamada y el MOS sale solo. Entrega una tabla con las 10 llamadas y el promedio.

---

## 6. Texto para el informe (sección «Telefonía IP»)

Redacta de 1 a 1,5 páginas, en tercera persona y tono técnico, con:
- Qué se configuró: SIP sobre TLS y SRTP, y por qué (cifrar señalización y audio).
- La comparación antes/después de Wireshark.
- Resultados de SIPp y la tabla de MOS, comparados con la meta del SLA (MOS ≥ 4.0, pérdida ≤ 1 %, jitter ≤ 30 ms, RTT ≤ 300 ms).
- Una conclusión breve.

---

## Resumen de capturas que debes entregar

| Nombre | Qué muestra |
|---|---|
| TA3_RP_01_contenedores | Entorno levantado |
| TA3_RP_02_transporte-tls | Transporte TLS en el puerto 5061 |
| TA3_RP_03_linphone-tls | Linphone registrado por TLS |
| TA3_RP_04_llamada-cifrada | Llamada cifrada en Linphone |
| TA3_RP_05_sip-sin-cifrar | Wireshark: SIP legible por UDP |
| TA3_RP_06_sip-cifrado-tls | Wireshark: SIP cifrado por TLS |
| TA3_RP_07_sipp-resumen | Resumen de SIPp (10 llamadas) |
| TA3_RP_08_channelstats | Estadísticas de la llamada |

Cualquier duda, escribe al grupo con una captura del error. ¡Gracias!
