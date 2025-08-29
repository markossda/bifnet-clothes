FROM python:3.9-slim

# Install system dependencies - minimal for OpenCV headless
RUN apt-get update && apt-get install -y \
    libglib2.0-0 \
    libgomp1 \
    wget \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements first for better Docker layer caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create temp directory for API processing
RUN mkdir -p temp_api

# Pre-download BiRefNet model to avoid startup timeout
RUN python -c "
import os
os.environ['TRANSFORMERS_CACHE'] = '/app/models'
os.environ['HF_HOME'] = '/app/models'
from transformers import AutoModelForImageSegmentation
print('📥 Pre-downloading BiRefNet model...')
model = AutoModelForImageSegmentation.from_pretrained(
    'ZhengPeng7/BiRefNet',
    trust_remote_code=True,
    cache_dir='/app/models'
)
print('✅ BiRefNet model downloaded and cached!')
"

# Set environment variables
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1
ENV PORT=8080
ENV TRANSFORMERS_CACHE=/app/models
ENV HF_HOME=/app/models

# Expose port (Cloud Run uses PORT env var)
EXPOSE 8080

# Health check - extended timeouts for BiRefNet model loading
HEALTHCHECK --interval=60s --timeout=60s --start-period=300s --retries=5 \
    CMD python -c "import requests; requests.get('http://localhost:${PORT:-8080}/health')" || exit 1

# Start the API server (use PORT env var for Cloud Run compatibility)
CMD ["sh", "-c", "uvicorn api_server:app --host 0.0.0.0 --port ${PORT:-8080}"]