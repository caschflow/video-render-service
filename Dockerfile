# Dockerfile para servicio de renderizado de video
FROM python:3.10-alpine

# Instalar dependencias del sistema y compilación
RUN apk add --no-cache \
    ffmpeg \
    curl \
    bash \
    build-base \
    musl-dev \
    python3-dev \
    zlib-dev \
    jpeg-dev \
    freetype-dev \
    && rm -rf /var/cache/apk/*

# Directorio de trabajo
WORKDIR /app

# Copiar requerimientos en una capa separada (mejor caching)
COPY requirements.txt .

# Instalar dependencias de Python
RUN pip install --no-cache-dir -r requirements.txt

# Crear directorios necesarios
RUN mkdir -p /tmp/ffmpeg /app/output /app/logs

# Copiar código de la aplicación
COPY render_api.py /app/

# Exponer puerto
EXPOSE 8080

# Variables de entorno por defecto
ENV FFMPEG_THREADS=3 \
    MAX_CONCURRENT_JOBS=2 \
    TEMP_DIR=/tmp/ffmpeg \
    OUTPUT_DIR=/app/output

# Ejecutar aplicación con uvicorn
CMD ["uvicorn", "render_api:app", "--host", "0.0.0.0", "--port", "8080"]
