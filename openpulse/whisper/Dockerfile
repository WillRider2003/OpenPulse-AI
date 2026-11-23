FROM python:3.11-slim

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ffmpeg \
 && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir faster-whisper==1.1.0 requests

WORKDIR /app
COPY server.py /app/server.py

EXPOSE 9000
CMD ["python3", "/app/server.py"]
