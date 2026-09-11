FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

COPY . .

# Pre-download the rembg u2net model so the first BG-removal request
# doesn't silently block for ~60s while the model fetches at runtime.
RUN python -c "from rembg import remove; from PIL import Image; remove(Image.new('RGBA', (1, 1)))"

RUN chmod +x start.sh

EXPOSE 8080

CMD ["./start.sh"]
