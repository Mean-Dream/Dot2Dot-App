import asyncio
import os
from arq.connections import RedisSettings
from processing import process_dots


async def run_process_dots(
    ctx,
    project_id: str,
    sparsity: int,
    remove_bg: bool,
    erased_points: list,
):
    await asyncio.to_thread(process_dots, project_id, sparsity, remove_bg, erased_points)


class WorkerSettings:
    functions = [run_process_dots]
    redis_settings = RedisSettings.from_dsn(
        os.environ.get("REDIS_URL", "redis://localhost:6379")
    )
    # rembg loads a large ML model; cap at 2 concurrent jobs per instance
    # to avoid OOM. Extra jobs queue in Redis automatically.
    max_jobs = 2
    job_timeout = 300  # 5 minutes
