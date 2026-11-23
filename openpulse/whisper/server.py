#!/usr/bin/env python3
"""
OpenPulse AI - Microservicio Local de Transcripcion Whisper (faster-whisper - MIT)
Escucha en el puerto 9000 y recibe archivos de audio (.wav, .mp3, .m4a, .ogg, .webm)
por POST /transcribe, devolviendo JSON con segmentos con marcas de tiempo en espanol.
"""
import http.server
import json
import os
import tempfile
import time
from faster_whisper import WhisperModel

MODEL_NAME = os.environ.get("WHISPER_MODEL", "tiny")
print(f"[OpenPulse Whisper] Cargando modelo '{MODEL_NAME}' (CPU int8, licencia MIT)...", flush=True)
model = WhisperModel(MODEL_NAME, device="cpu", compute_type="int8")
print(f"[OpenPulse Whisper] Modelo '{MODEL_NAME}' listo en :9000", flush=True)

def fmt_ts(sec: float) -> str:
    s = int(max(0, sec))
    return f"{s // 3600:02d}:{(s % 3600) // 60:02d}:{s % 60:02d}"

class WhisperHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            body = json.dumps({"status": "ok", "model": MODEL_NAME, "license": "MIT"}).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        if not self.path.startswith("/transcribe"):
            self.send_response(404)
            self.end_headers()
            return
        length = int(self.headers.get("Content-Length", 0))
        ext = self.headers.get("X-File-Ext", ".wav")
        if not ext.startswith("."):
            ext = "." + ext
        data = self.rfile.read(length)
        t0 = time.perf_counter()
        tmp_path = None
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix=ext) as tmp:
                tmp.write(data)
                tmp_path = tmp.name
            segments_iter, info = model.transcribe(tmp_path, language="es", beam_size=1)
            segments = []
            full_text = []
            for seg in segments_iter:
                txt = seg.text.strip()
                if txt:
                    segments.append({
                        "start": fmt_ts(seg.start),
                        "end": fmt_ts(seg.end),
                        "text": txt
                    })
                    full_text.append(txt)
            elapsed = round(time.perf_counter() - t0, 2)
            resp = {
                "model": MODEL_NAME,
                "language": info.language,
                "language_probability": round(float(info.language_probability) * 100.0, 1),
                "duration_sec": round(float(info.duration), 2),
                "elapsed_sec": elapsed,
                "text": " ".join(full_text),
                "segments": segments
            }
            body = json.dumps(resp, ensure_ascii=False).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except Exception as e:
            err = json.dumps({"error": str(e)}).encode("utf-8")
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(err)))
            self.end_headers()
            self.wfile.write(err)
        finally:
            if tmp_path and os.path.exists(tmp_path):
                try:
                    os.remove(tmp_path)
                except Exception:
                    pass

    def log_message(self, format, *args):
        return

if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("0.0.0.0", 9000), WhisperHandler)
    server.serve_forever()
