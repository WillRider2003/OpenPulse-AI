#!/usr/bin/env python3
"""
OpenPulse AI - Exportador Prometheus de Metricas del SLA en Tiempo Real (:9105/metrics)
Sondea continuamente los servicios reales de la red Docker (Nextcloud, Collabora,
Keycloak, Caddy HTTPS, Valkey y Asterisk SIP-TLS) y expone las metricas de
disponibilidad, latencia, calidad de voz (MOS/Jitter) y KPIs de colaboracion
para el tablero "OpenPulse AI - SLA" en Grafana OSS.
"""
import http.server
import json
import socket
import ssl
import subprocess
import time
import urllib.request

PORT = 9105

def probe_http(url: str) -> tuple[int, float]:
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    t0 = time.perf_counter()
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "OpenPulse-SLA-Exporter/3.0"})
        with urllib.request.urlopen(req, timeout=2.5, context=ctx) as resp:
            resp.read(128)
        ms = round((time.perf_counter() - t0) * 1000.0, 2)
        return 1, ms
    except Exception:
        ms = round((time.perf_counter() - t0) * 1000.0, 2)
        return 0, ms

def probe_tcp(host: str, port: int) -> tuple[int, float]:
    t0 = time.perf_counter()
    try:
        with socket.create_connection((host, port), timeout=2.0):
            ms = round((time.perf_counter() - t0) * 1000.0, 2)
            return 1, ms
    except Exception:
        ms = round((time.perf_counter() - t0) * 1000.0, 2)
        return 0, ms

CODECS = ("ulaw", "alaw", "opus", "g722", "gsm")


def mos_modelo_e(rtt_ms: float, jitter_ms: float, loss_pct: float) -> float:
    """Modelo E simplificado (ITU-T G.107), mismo calculo que la hoja calculo_mos.xlsx."""
    ef = rtt_ms / 2.0 + 2.0 * jitter_ms + 10.0
    if ef < 160:
        r = 93.2 - ef / 40.0 - 2.5 * loss_pct
    else:
        r = 93.2 - (ef - 120.0) / 10.0 - 2.5 * loss_pct
    r = max(0.0, min(100.0, r))
    return round(1 + 0.035 * r + 7e-6 * r * (r - 60) * (100 - r), 2)


def leer_voz_asterisk() -> list:
    """Devuelve una lista de canales activos con jitter, perdida y RTT REALES.
    Si no hay llamadas, la lista queda vacia y Prometheus no recibe valores de voz."""
    canales = []
    try:
        out = subprocess.check_output(["asterisk", "-rx", "pjsip show channelstats"],
                                      stderr=subprocess.DEVNULL, text=True, timeout=2)
    except Exception:
        return canales
    for line in out.splitlines():
        tok = line.split()
        idx = next((i for i, t in enumerate(tok) if t in CODECS), None)
        if idx is None or len(tok) < idx + 10:
            continue
        try:
            rx_count, rx_lost = int(tok[idx + 1]), int(tok[idx + 2])
            rx_jit = float(tok[idx + 4])
            rtt = float(tok[idx + 9])
        except ValueError:
            continue
        loss = 100.0 * rx_lost / rx_count if rx_count else 0.0
        canal = {"canal": tok[idx - 2], "jitter_ms": round(rx_jit * 1000, 2), "loss_pct": round(loss, 3), "rtt_ms": round(rtt * 1000, 2)}
        if canal["rtt_ms"] > 0:  # sin RTCP valido no se estima el MOS
            canal["mos"] = mos_modelo_e(canal["rtt_ms"], canal["jitter_ms"], canal["loss_pct"])
        canales.append(canal)
    return canales


def leer_kpi_colaboracion() -> dict:
    """Valores medidos por los scripts de prueba (chat, presencia, documentos), si existen."""
    try:
        with open("/opt/openpulse/scripts/kpi_colaboracion.json", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


class MetricsHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return

        servicios = [
            ("nextcloud",   *probe_http("http://nextcloud:80/status.php")),
            ("collabora",   *probe_http("http://collabora:9980/hosting/discovery")),
            ("keycloak",    *probe_http("http://keycloak:8080/realms/openpulse")),
            ("caddy-https", *probe_tcp("caddy", 8443)),
            ("asterisk",    *probe_tcp("127.0.0.1", 5061)),
            ("valkey",      *probe_tcp("valkey", 6379)),
        ]

        canales = leer_voz_asterisk()
        kpi = leer_kpi_colaboracion()

        lines = [
            "# HELP openpulse_service_up Estado operativo del servicio (1 = Activo, 0 = Caido)",
            "# TYPE openpulse_service_up gauge",
        ]
        for name, up, _ in servicios:
            lines.append(f'openpulse_service_up{{servicio="{name}"}} {up}')

        lines += [
            "# HELP openpulse_service_latency_ms Tiempo de respuesta real medido por servicio en ms",
            "# TYPE openpulse_service_latency_ms gauge",
        ]
        for name, _, lat in servicios:
            lines.append(f'openpulse_service_latency_ms{{servicio="{name}"}} {lat}')

        # Voz: solo se publican valores si hay llamadas activas (sin llamadas, Grafana muestra "No data")
        lines += [
            "# HELP openpulse_voice_jitter_ms Jitter recibido por canal (RTCP de Asterisk)",
            "# TYPE openpulse_voice_jitter_ms gauge",
            "# HELP openpulse_voice_loss_pct Perdida recibida por canal en porcentaje",
            "# TYPE openpulse_voice_loss_pct gauge",
            "# HELP openpulse_voice_rtt_ms RTT por canal (RTCP de Asterisk)",
            "# TYPE openpulse_voice_rtt_ms gauge",
            "# HELP openpulse_voice_mos_score MOS estimado con el modelo E por canal (solo con RTT valido)",
            "# TYPE openpulse_voice_mos_score gauge",
        ]
        for c in canales:
            et = f'canal="{c["canal"]}"'
            lines.append(f"openpulse_voice_jitter_ms{{{et}}} {c['jitter_ms']}")
            lines.append(f"openpulse_voice_loss_pct{{{et}}} {c['loss_pct']}")
            lines.append(f"openpulse_voice_rtt_ms{{{et}}} {c['rtt_ms']}")
            if "mos" in c:
                lines.append(f"openpulse_voice_mos_score{{{et}}} {c['mos']}")
        if canales:
            cumplen = sum(1 for c in canales if c["jitter_ms"] <= 30 and c["loss_pct"] <= 1 and 0 < c["rtt_ms"] <= 300)
            lines += [
                "# HELP openpulse_voice_sla_compliant_ratio Porcentaje de canales activos dentro de los umbrales del SLA",
                "# TYPE openpulse_voice_sla_compliant_ratio gauge",
                f"openpulse_voice_sla_compliant_ratio {round(100.0 * cumplen / len(canales), 1)}",
            ]

        # Colaboracion: solo valores medidos por los scripts de prueba
        if kpi:
            lines += [
                "# HELP openpulse_collab_kpi_ms KPI de colaboracion medido por pruebas sinteticas (ms)",
                "# TYPE openpulse_collab_kpi_ms gauge",
            ]
            for nombre, valor in kpi.items():
                lines.append(f'openpulse_collab_kpi_ms{{kpi="{nombre}"}} {float(valor)}')

        body = ("\n".join(lines) + "\n").encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return

if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), MetricsHandler)
    print(f"[OpenPulse AI] Exportador Prometheus SLA activo en :{PORT}/metrics", flush=True)
    server.serve_forever()
