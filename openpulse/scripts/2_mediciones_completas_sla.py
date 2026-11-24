#!/usr/bin/env python3
"""
OpenPulse AI - Calculo de indicadores del SLA a partir de mediciones REALES (TA3)

No contiene resultados escritos en el codigo. Hace dos cosas:
  1. Lee un CSV de llamadas medidas (una fila por llamada) y calcula el MOS con el
     modelo E simplificado, el p95 del jitter y el % de llamadas dentro del SLA.
       canal,jitter_ms,perdida_pct,rtt_ms
       llamada1,4.0,0.00,33
     Los valores se copian de "pjsip show channelstats" (jitter y RTT vienen en segundos).
  2. Mide el tiempo de respuesta real de los accesos HTTPS del portal (p95 de N sondeos).

Uso:
  python scripts/2_mediciones_completas_sla.py --llamadas mediciones/llamadas.csv --ip 10.x.x.x
"""
import argparse
import csv
import math
import ssl
import time
import urllib.request


def mos_modelo_e(rtt_ms, jitter_ms, perdida_pct):
    ef = rtt_ms / 2.0 + 2.0 * jitter_ms + 10.0
    if ef < 160:
        r = 93.2 - ef / 40.0 - 2.5 * perdida_pct
    else:
        r = 93.2 - (ef - 120.0) / 10.0 - 2.5 * perdida_pct
    r = max(0.0, min(100.0, r))
    return r, 1 + 0.035 * r + 7e-6 * r * (r - 60) * (100 - r)


def p95(valores):
    orden = sorted(valores)
    return orden[max(0, math.ceil(0.95 * len(orden)) - 1)]


def sondear(url, n):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    tiempos, fallos = [], 0
    for _ in range(n):
        t0 = time.perf_counter()
        try:
            with urllib.request.urlopen(url, timeout=5, context=ctx) as r:
                r.read(256)
            tiempos.append((time.perf_counter() - t0) * 1000)
        except Exception:
            fallos += 1
        time.sleep(0.5)
    return tiempos, fallos


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--llamadas", help="CSV con canal,jitter_ms,perdida_pct,rtt_ms")
    ap.add_argument("--ip", help="IP del servidor para sondear los accesos HTTPS")
    ap.add_argument("--sondeos", type=int, default=20)
    a = ap.parse_args()
    print(time.strftime("%Y-%m-%d %H:%M:%S %z"))

    if a.llamadas:
        filas = list(csv.DictReader(open(a.llamadas, encoding="utf-8")))
        print(f"\n[VOZ] {len(filas)} llamadas leidas de {a.llamadas}")
        print(f"{'canal':<18}{'jitter':>9}{'perdida':>10}{'RTT':>8}{'R':>8}{'MOS':>7}  SLA")
        dentro, jitters = 0, []
        for f in filas:
            j, p, rtt = float(f["jitter_ms"]), float(f["perdida_pct"]), float(f["rtt_ms"])
            jitters.append(j)
            if rtt <= 0:
                print(f"{f['canal']:<18}{j:>8.1f} {p:>8.2f}%{'—':>8}{'—':>8}{'—':>7}  sin RTT valido")
                continue
            r, mos = mos_modelo_e(rtt, j, p)
            ok = j <= 30 and p <= 1 and rtt <= 300
            dentro += ok
            print(f"{f['canal']:<18}{j:>8.1f} {p:>8.2f}%{rtt:>8.0f}{r:>8.1f}{mos:>7.2f}  {'cumple' if ok else 'NO cumple'}")
        print(f"\nJitter p95: {p95(jitters):.1f} ms (meta <= 30 ms)")
        print(f"Llamadas dentro de los tres umbrales: {dentro} de {len(filas)} (meta >= 95 %)")

    if a.ip:
        for nombre, url in [("Portal Nextcloud", f"https://{a.ip}:8443/status.php"),
                            ("Keycloak", f"https://{a.ip}:8444/realms/openpulse"),
                            ("Collabora", f"https://{a.ip}:9443/hosting/discovery")]:
            t, fallos = sondear(url, a.sondeos)
            if t:
                print(f"[HTTPS] {nombre}: {len(t)} respuestas, media {sum(t)/len(t):.0f} ms, p95 {p95(t):.0f} ms, fallos {fallos}")
            else:
                print(f"[HTTPS] {nombre}: sin respuesta ({fallos} fallos)")


if __name__ == "__main__":
    main()
