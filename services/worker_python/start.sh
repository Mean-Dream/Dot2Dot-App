#!/bin/sh
# Start the ARQ worker in the background, then uvicorn in the foreground.
# Cloud Run keeps the container alive as long as uvicorn (PID 1) is running.
python -m arq worker.WorkerSettings &
exec python -m uvicorn main:app --host 0.0.0.0 --port 8080
