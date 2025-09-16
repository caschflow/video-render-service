#!/usr/bin/env python3
"""
API de Renderizado de Video
Combina video + audio usando FFmpeg
"""

import os
import uuid
import asyncio
import subprocess
import logging
from pathlib import Path
from typing import Optional, Dict, Any
from datetime import datetime
import json
import psutil
import aiofiles
import requests

from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.responses import FileResponse
from pydantic import BaseModel, HttpUrl

# Configuración de logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/app/logs/render.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Configuración desde variables de entorno
FFMPEG_THREADS = int(os.getenv('FFMPEG_THREADS', '3'))
MAX_CONCURRENT_JOBS = int(os.getenv('MAX_CONCURRENT_JOBS', '2'))
TEMP_DIR = Path(os.getenv('TEMP_DIR', '/tmp/ffmpeg'))
OUTPUT_DIR = Path(os.getenv('OUTPUT_DIR', '/app/output'))

# Crear directorios si no existen
TEMP_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# FastAPI app
app = FastAPI(
    title="Video Render API",
    description="API para renderizado de video con audio",
    version="1.0.0"
)

# Estado global de trabajos
jobs_status: Dict[str, Dict[str, Any]] = {}
active_jobs = 0

class RenderRequest(BaseModel):
    video_url: HttpUrl
    audio_url: HttpUrl
    quality: str = "high"  # high, medium, low
    
class JobStatus(BaseModel):
    job_id: str
    status: str  # pending, processing, completed, failed
    progress: int = 0
    message: str = ""
    created_at: str
    completed_at: Optional[str] = None
    output_file: Optional[str] = None
    error: Optional[str] = None

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    cpu_percent = psutil.cpu_percent(interval=1)
    memory = psutil.virtual_memory()
    disk_usage = psutil.disk_usage(str(OUTPUT_DIR))
    
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "system": {
            "cpu_usage": f"{cpu_percent}%",
            "memory_usage": f"{memory.percent}%",
            "disk_free": f"{disk_usage.free // (1024**3)}GB",
            "active_jobs": active_jobs,
            "max_jobs": MAX_CONCURRENT_JOBS
        },
        "ffmpeg_version": get_ffmpeg_version()
    }

def get_ffmpeg_version():
    """Obtener versión de FFmpeg"""
    try:
        result = subprocess.run(
            ['ffmpeg', '-version'], 
            capture_output=True, 
            text=True, 
            timeout=10
        )
        return result.stdout.split('\n')[0] if result.returncode == 0 else "Unknown"
    except Exception:
        return "FFmpeg not available"

@app.post("/render")
async def create_render_job(request: RenderRequest, background_tasks: BackgroundTasks):
    """Crear nuevo trabajo de renderizado"""
    global active_jobs
    
    # Verificar límite de trabajos concurrentes
    if active_jobs >= MAX_CONCURRENT_JOBS:
        raise HTTPException(
            status_code=429, 
            detail=f"Maximum concurrent jobs ({MAX_CONCURRENT_JOBS}) reached. Try again later."
        )
    
    # Generar ID único para el trabajo
    job_id = str(uuid.uuid4())[:8]
    
    # Registrar trabajo
    jobs_status[job_id] = {
        "job_id": job_id,
        "status": "pending",
        "progress": 0,
        "message": "Job queued for processing",
        "created_at": datetime.now().isoformat(),
        "video_url": str(request.video_url),
        "audio_url": str(request.audio_url),
        "quality": request.quality
    }
    
    # Iniciar procesamiento en background
    background_tasks.add_task(process_render_job, job_id, request)
    active_jobs += 1
    
    logger.info(f"Created render job: {job_id}")
    return {"job_id": job_id, "status": "pending", "message": "Job created successfully"}

@app.get("/status/{job_id}")
async def get_job_status(job_id: str):
    """Obtener estado de un trabajo"""
    if job_id not in jobs_status:
        raise HTTPException(status_code=404, detail="Job not found")
    
    return jobs_status[job_id]

@app.get("/download/{filename}")
async def download_file(filename: str):
    """Descargar archivo de salida"""
    file_path = OUTPUT_DIR / filename
    
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="File not found")
    
    return FileResponse(
        path=str(file_path),
        filename=filename,
        media_type='video/mp4'
    )

@app.get("/jobs")
async def list_jobs():
    """Listar todos los trabajos"""
    return {
        "total_jobs": len(jobs_status),
        "active_jobs": active_jobs,
        "jobs": list(jobs_status.values())
    }

async def process_render_job(job_id: str, request: RenderRequest):
    """Procesar trabajo de renderizado"""
    global active_jobs
    
    try:
        # Actualizar estado
        jobs_status[job_id]["status"] = "processing"
        jobs_status[job_id]["message"] = "Starting download"
        jobs_status[job_id]["progress"] = 10
        
        # Descargar archivos
        video_path = await download_file_async(request.video_url, job_id, "video")
        jobs_status[job_id]["progress"] = 30
        
        audio_path = await download_file_async(request.audio_url, job_id, "audio")
        jobs_status[job_id]["progress"] = 50
        
        # Renderizar video
        jobs_status[job_id]["message"] = "Processing video"
        output_path = await render_video(video_path, audio_path, job_id, request.quality)
        jobs_status[job_id]["progress"] = 90
        
        # Completar trabajo
        jobs_status[job_id].update({
            "status": "completed",
            "progress": 100,
            "message": "Rendering completed successfully",
            "completed_at": datetime.now().isoformat(),
            "output_file": output_path.name
        })
        
        # Limpiar archivos temporales
        cleanup_temp_files([video_path, audio_path])
        
        logger.info(f"Job {job_id} completed successfully")
        
    except Exception as e:
        error_msg = str(e)
        logger.error(f"Job {job_id} failed: {error_msg}")
        
        jobs_status[job_id].update({
            "status": "failed",
            "message": f"Rendering failed: {error_msg}",
            "error": error_msg,
            "completed_at": datetime.now().isoformat()
        })
    
    finally:
        active_jobs -= 1

async def download_file_async(url: HttpUrl, job_id: str, file_type: str) -> Path:
    """Descargar archivo de forma asíncrona"""
    try:
        response = requests.get(str(url), stream=True, timeout=60)
        response.raise_for_status()
        
        # Determinar extensión basada en content-type o URL
        content_type = response.headers.get('content-type', '')
        if file_type == "video":
            extension = ".mp4"
        elif file_type == "audio":
            extension = ".wav" if "wav" in content_type or str(url).endswith(".wav") else ".mp3"
        else:
            extension = ""
            
        file_path = TEMP_DIR / f"{job_id}_{file_type}{extension}"
        
        async with aiofiles.open(file_path, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                await f.write(chunk)
        
        logger.info(f"Downloaded {file_type} for job {job_id}: {file_path}")
        return file_path
        
    except Exception as e:
        raise Exception(f"Failed to download {file_type}: {str(e)}")

async def render_video(video_path: Path, audio_path: Path, job_id: str, quality: str) -> Path:
    """Renderizar video con audio usando FFmpeg"""
    output_file = OUTPUT_DIR / f"render_{job_id}.mp4"
    
    # Configuración de calidad
    quality_settings = {
        "high": ["-crf", "18", "-preset", "medium"],
        "medium": ["-crf", "23", "-preset", "fast"], 
        "low": ["-crf", "28", "-preset", "ultrafast"]
    }
    
    # Comando FFmpeg
    cmd = [
        "ffmpeg", "-y",
        "-i", str(video_path),
        "-i", str(audio_path),
        "-c:v", "libx264",
        "-c:a", "aac",
        "-threads", str(FFMPEG_THREADS),
        *quality_settings.get(quality, quality_settings["medium"]),
        "-movflags", "+faststart",
        str(output_file)
    ]
    
    logger.info(f"Starting FFmpeg render for job {job_id}")
    
    # Ejecutar FFmpeg
    process = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE
    )
    
    stdout, stderr = await process.communicate()
    
    if process.returncode != 0:
        error_msg = stderr.decode('utf-8')
        logger.error(f"FFmpeg error for job {job_id}: {error_msg}")
        raise Exception(f"FFmpeg rendering failed: {error_msg}")
    
    if not output_file.exists():
        raise Exception("Output file was not created")
    
    logger.info(f"Video rendering completed for job {job_id}")
    return output_file

def cleanup_temp_files(file_paths: list):
    """Limpiar archivos temporales"""
    for path in file_paths:
        try:
            if path and path.exists():
                path.unlink()
        except Exception as e:
            logger.warning(f"Failed to cleanup {path}: {e}")

if __name__ == "__main__":
    import uvicorn
    
    logger.info("Starting Video Render API...")
    logger.info(f"FFmpeg threads: {FFMPEG_THREADS}")
    logger.info(f"Max concurrent jobs: {MAX_CONCURRENT_JOBS}")
    logger.info(f"Temp directory: {TEMP_DIR}")
    logger.info(f"Output directory: {OUTPUT_DIR}")
    
    uvicorn.run(
        app, 
        host="0.0.0.0", 
        port=8080,
        log_level="info"
    )
