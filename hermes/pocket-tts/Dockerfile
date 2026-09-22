FROM --platform=linux/amd64 python:3.12-slim
ENV PIP_NO_CACHE_DIR=1 HF_HOME=/models
RUN pip install --quiet pocket-tts --extra-index-url https://download.pytorch.org/whl/cpu
# Pre-download the model and the default voice so the container needs no network at runtime.
RUN pocket-tts generate --text "Hello from prometheus." --voice alba --output-path /tmp/warm.wav && rm -f /tmp/warm.wav
EXPOSE 8123
CMD ["pocket-tts", "serve", "--host", "0.0.0.0", "--port", "8123"]
