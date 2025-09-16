# Dockerfile para servicio de renderizado de video
FROM python:3.10-alpine

# Instalar FFmpeg y dependencias del sistema
RUN apk add --no-cache \
    ffmpeg \
    curl \
    bash \
    && rm -rf /var/cache/apk/*

# Crear directorio de trabajo
WORKDIR /app

# Instalar dependencias de Python
RUN pip install --no-cache-dir \
    fastapi==0.104.1 \
    uvicorn[standard]==0.24.0 \
    requests==2.31.0 \
    pillow==10.1.0 \
    psutil==5.9.6 \
    aiofiles==23.2.1

# Crear directorios necesarios
RUN mkdir -p /tmp/ffmpeg /app/output /app/logs

# Copiar el archivo de la aplicación
COPY render_api.py /app/

# Exponer el puerto
EXPOSE 8080

# Variables de entorno por defecto
ENV FFMPEG_THREADS=3
ENV MAX_CONCURRENT_JOBS=2
ENV TEMP_DIR=/tmp/ffmpeg
ENV OUTPUT_DIR=/app/output

# Comando para ejecutar la aplicación
CMD ["python", "render_api.py"]
