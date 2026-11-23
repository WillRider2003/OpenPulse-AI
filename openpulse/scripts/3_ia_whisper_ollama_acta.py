#!/usr/bin/env python3
r"""
OpenPulse AI - Asistente de Edge AI Local REAL (Whisper MIT + Ollama Qwen2.5 Apache-2.0)
Hito 22 nov (TA3) - Reto Optativo de IA + Leccion 14 (Edge AI y Privacy by Design)

Uso en vivo frente a los Jefes de Practica:
  1. Con un audio real recien grabado (WAV, M4A, MP3, OGG):
       python .\scripts\3_ia_whisper_ollama_acta.py --audio "ruta\a\mi_grabacion.m4a"
  2. Con un texto dictado en el momento por el JP:
       python .\scripts\3_ia_whisper_ollama_acta.py --texto "Acuerdo 1: Abdon revisa el video el martes..."
  3. Sin argumentos (usa el audio real de prueba 'scripts/audio_prueba_reunion.wav'):
       python .\scripts\3_ia_whisper_ollama_acta.py

El script envia el audio a Whisper local (:9000), envia la transcripcion real a Ollama
local (:11434, modelo qwen2.5:0.5b Apache-2.0), genera 'Acta_Reunion_Andes_IA.md' y la
sube e indexa automaticamente dentro de Nextcloud Files para abrirla en Collabora.
"""
import argparse
import datetime
import json
import os
import subprocess
import time
import urllib.request

REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_AUDIO = os.path.join(REPO_DIR, "scripts", "audio_prueba_reunion.wav")
OUTPUT_ACTA = os.path.join(REPO_DIR, "Acta_Reunion_Andes_IA.md")
WHISPER_URL = "http://127.0.0.1:9000/transcribe"
OLLAMA_URL = "http://127.0.0.1:11434/api/generate"
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "qwen2.5:0.5b")

def transcribir_whisper_real(ruta_audio: str) -> dict:
    """Envia un archivo de audio real al contenedor local de Whisper (:9000)."""
    ext = os.path.splitext(ruta_audio)[1] or ".wav"
    with open(ruta_audio, "rb") as f:
        audio_bytes = f.read()
    req = urllib.request.Request(
        WHISPER_URL,
        data=audio_bytes,
        headers={
            "Content-Type": "application/octet-stream",
            "X-File-Ext": ext
        },
        method="POST"
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode("utf-8"))

def resumir_ollama_real(transcripcion: str) -> tuple[str, float]:
    """Envia la transcripcion real al modelo local Ollama (qwen2.5:0.5b - Apache-2.0)."""
    prompt = (
        "Eres el asistente de actas de una empresa contable llamada Estudio Contable Andes & Asociados. "
        "A partir de la siguiente transcripcion de una reunion en espanol, redacta de forma clara y concisa:\n"
        "1) Un 'Resumen Ejecutivo' en un solo parrafo.\n"
        "2) Una lista de 'Acuerdos y Tareas' con viñetas indicando accion y responsable si se mencionan.\n"
        "Responde unicamente en espanol y basandote estrictamente en lo que dice la transcripcion.\n\n"
        f"TRANSCRIPCION:\n{transcripcion}\n"
    )
    payload = json.dumps({
        "model": OLLAMA_MODEL,
        "prompt": prompt,
        "stream": False,
        "options": {"temperature": 0.2, "num_predict": 320}
    }).encode("utf-8")
    t0 = time.perf_counter()
    req = urllib.request.Request(
        OLLAMA_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    with urllib.request.urlopen(req, timeout=180) as resp:
        data = json.loads(resp.read().decode("utf-8"))
        elapsed = round(time.perf_counter() - t0, 2)
        return data.get("response", "").strip(), elapsed

def publicar_acta_en_nextcloud(ruta_acta: str, nombre_archivo: str = "Acta_Reunion_Andes_IA.md"):
    """Copia el Acta generada directamente a las carpetas de Nextcloud de los usuarios."""
    try:
        res = subprocess.run(
            ["docker", "ps", "--format", "{{.Names}}"],
            capture_output=True, text=True, timeout=5
        )
        contenedores = [c.strip() for c in res.stdout.splitlines() if "nextcloud" in c]
        if not contenedores:
            return
        nc_container = contenedores[0]
        print(f"\n[Paso 4/4] Publicando '{nombre_archivo}' automaticamente en Nextcloud Hub ({nc_container})...")
        for user in ["admin", "wantaurco", "lgil", "avallejo", "rpretel", "lparedes"]:
            dest_dir = f"/var/www/html/data/{user}/files"
            subprocess.run(["docker", "exec", nc_container, "sh", "-c", f"mkdir -p {dest_dir}"], capture_output=True, timeout=5)
            subprocess.run(["docker", "cp", ruta_acta, f"{nc_container}:{dest_dir}/{nombre_archivo}"], capture_output=True, timeout=5)
            subprocess.run(["docker", "exec", nc_container, "chown", "-R", "www-data:www-data", dest_dir], capture_output=True, timeout=5)
        subprocess.run(["docker", "exec", "-u", "www-data", nc_container, "php", "occ", "files:scan", "--all"], capture_output=True, timeout=20)
        print(f"  -> [OK] '{nombre_archivo}' ya esta visible en Nextcloud Files de todos los integrantes.")
    except Exception as e:
        print(f"  -> (Aviso Nextcloud: {e})")

def main():
    parser = argparse.ArgumentParser(description="OpenPulse AI - Pipeline Local Real (Whisper + Ollama)")
    parser.add_argument("--audio", help="Ruta al archivo de audio real (.wav, .m4a, .mp3, .ogg)")
    parser.add_argument("--texto", help="Texto directo dictado para resumir con Ollama sin paso de audio")
    parser.add_argument("--salida", default="Acta_Reunion_Andes_IA.md", help="Nombre del archivo en Nextcloud")
    args = parser.parse_args()

    t_inicio = time.perf_counter()
    print("==============================================================================")
    print(" [OpenPulse AI - TA3] EDGE AI LOCAL REAL (Whisper MIT + Ollama Qwen2.5 Apache-2.0)")
    print(" Procesamiento 100 % en el servidor local - 0 bytes enviados a nubes externas")
    print("==============================================================================")

    segmentos = []
    texto_transcrito = ""
    origen_desc = ""
    tiempo_whisper = 0.0

    if args.texto:
        print("\n[Paso 1/4] Usando texto dictado en vivo...")
        texto_transcrito = args.texto.strip()
        origen_desc = "Dictado directo en vivo"
        segmentos = [{"start": "00:00:00", "end": "00:00:10", "text": texto_transcrito}]
        print(f"  -> Texto recibido: \"{texto_transcrito}\"")
    else:
        ruta_audio = args.audio or DEFAULT_AUDIO
        if not os.path.exists(ruta_audio):
            print(f"[ERROR] No se encontro el archivo de audio: {ruta_audio}")
            print("  Pasa un audio con: python .\\scripts\\3_ia_whisper_ollama_acta.py --audio tu_audio.wav")
            return
        origen_desc = os.path.basename(ruta_audio)
        print(f"\n[Paso 1/4] Transcribiendo audio real con Whisper local ({WHISPER_URL})...")
        print(f"  -> Archivo: {ruta_audio}")
        res_w = transcribir_whisper_real(ruta_audio)
        texto_transcrito = res_w.get("text", "").strip()
        segmentos = res_w.get("segments", [])
        tiempo_whisper = res_w.get("elapsed_sec", 0.0)
        print(f"  -> [OK] Whisper ({res_w.get('model')}, licencia MIT) | Idioma: {res_w.get('language')} ({res_w.get('language_probability')} %) | Duracion audio: {res_w.get('duration_sec')} s | Tiempo STT: {tiempo_whisper} s")
        print("\n--- Transcripcion REAL generada por Whisper ---")
        for seg in segmentos:
            print(f"  [{seg['start']} - {seg['end']}] {seg['text']}")

    print(f"\n[Paso 2/4] Generando Resumen Ejecutivo y Acuerdos con Ollama local (modelo '{OLLAMA_MODEL}', Apache-2.0)...")
    resumen_ia, tiempo_ollama = resumir_ollama_real(texto_transcrito)
    print(f"  -> [OK] Respuesta generada localmente en {tiempo_ollama} s")
    print("\n--- Sintesis REAL generada por Ollama (Qwen2.5) ---")
    print(resumen_ia)

    ahora = datetime.datetime.now().strftime("%d/%m/%Y %H:%M:%S")
    total_s = round(time.perf_counter() - t_inicio, 2)

    acta_md = f"""# Acta Automática de Reunión — Estudio Contable Andes & Asociados S.A.C.

- **Plataforma:** OpenPulse AI (Nextcloud Hub + Edge AI Local)
- **Fecha y hora de generación:** {ahora}
- **Fuente procesada:** `{origen_desc}`
- **Motores de IA (100 % Software Libre OSI):** `faster-whisper` (`MIT`, tiempo STT: {tiempo_whisper} s) + `Ollama` (`MIT`) con modelo `{OLLAMA_MODEL}` (`Apache-2.0`, tiempo LLM: {tiempo_ollama} s)
- **Privacidad (Lección 14 / Ley N.° 29733):** Procesamiento 100 % local en el servidor del cliente (0 bytes enviados a servicios en la nube)

---

## 1. Síntesis y Acuerdos Generados por IA Local (`{OLLAMA_MODEL}`)

{resumen_ia}

---

## 2. Transcripción Literal con Marcas de Tiempo (Whisper STT)

"""
    for seg in segmentos:
        acta_md += f"- **`[{seg['start']} - {seg['end']}]`** {seg['text']}\n"

    ruta_salida_local = os.path.join(REPO_DIR, args.salida)
    with open(ruta_salida_local, "w", encoding="utf-8") as f:
        f.write(acta_md)

    print(f"\n[Paso 3/4] Acta guardada localmente en: {ruta_salida_local}")
    publicar_acta_en_nextcloud(ruta_salida_local, args.salida)
    print(f"\n[LISTO] Tiempo total Edge AI real: {total_s} s | 0 bytes enviados a la nube.")
    print("==============================================================================")

if __name__ == "__main__":
    main()
