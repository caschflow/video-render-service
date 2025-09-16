# Dockerfile para servicio de renderizado de video
FROM python:3.10-slim AS base

# Instalar dependencias del sistema
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    curl \
    bash \
    build-essential \
    libjpeg-dev \
    zlib1g-dev \
    libfreetype6-dev \
    && rm -rf /var/lib/apt/lists/*

# Directorio de trabajo
WORKDIR /app

# Copiar requerimientos primero (cache)
COPY requirements.txt .

# Instalar dependencias de Python
RUN pip install --no-cache-dir -r requirements.txt

# Crear directorios necesarios
RUN mkdir -p /tmp/ffmpeg /app/output /app/logs

# Copiar el resto del código
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
