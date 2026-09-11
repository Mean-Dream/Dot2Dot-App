import base64
import os
import uuid
from contextlib import asynccontextmanager
from typing import Optional

from arq.connections import ArqRedis, create_pool, RedisSettings
from dotenv import load_dotenv
from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from supabase import create_client, Client

load_dotenv()

supabase: Client = create_client(
    os.environ["SUPABASE_URL"],
    os.environ["SUPABASE_SERVICE_ROLE_KEY"],
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.redis = await create_pool(
        RedisSettings.from_dsn(os.environ.get("REDIS_URL", "redis://localhost:6379"))
    )
    yield
    await app.state.redis.aclose()


app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Request models ────────────────────────────────────────────────────────────

class UploadPayload(BaseModel):
    image: str          # base64-encoded image bytes
    name: str
    sparsity: int = 20
    removeBg: bool = False
    userId: str
    projectId: Optional[str] = None   # set when re-generating for an existing project
    erased_points: list = []


class ProjectPayload(BaseModel):
    projectId: str
    sparsity: int = 20
    removeBg: bool = False
    erased_points: list = []


class ReprocessPayload(BaseModel):
    projectId: str
    sparsity: int = 20


# ── Helpers ───────────────────────────────────────────────────────────────────

def _current_user(authorization: str) -> str:
    """Validate a Bearer JWT and return the user_id, or raise 401."""
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing Bearer token")
    token = authorization[len("Bearer "):]
    try:
        user = supabase.auth.get_user(token)
        return user.user.id
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Invalid token: {e}")


# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.post("/upload")
async def upload_image(payload: UploadPayload):
    """
    Receives a base64-encoded image from the Flutter client, creates (or
    updates) a project row, uploads the image to Supabase Storage, then
    enqueues the dot-generation job.  Returns {"projectId": "..."}.
    """
    redis: ArqRedis = app.state.redis

    # 1. Decode image bytes
    try:
        img_bytes = base64.b64decode(payload.image)
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid base64 image data")

    # 2. Determine content-type from magic bytes (PNG vs JPEG)
    content_type = "image/png" if img_bytes[:8] == b"\x89PNG\r\n\x1a\n" else "image/jpeg"
    ext = "png" if content_type == "image/png" else "jpg"

    project_id = payload.projectId

    if project_id:
        # Re-generating for an existing project: reset status, keep image.
        supabase.table("projects").update({
            "status": "processing",
            "sparsity": payload.sparsity,
            "remove_bg": payload.removeBg,
        }).eq("id", project_id).execute()
    else:
        # New project: insert row and upload image to storage.
        display_name = payload.name.rsplit(".", 1)[0] if "." in payload.name else payload.name
        row = supabase.table("projects").insert({
            "user_id": payload.userId,
            "name": display_name,
            "status": "processing",
            "sparsity": payload.sparsity,
            "remove_bg": payload.removeBg,
        }).execute()
        project_id = row.data[0]["id"]

        image_path = f"{payload.userId}/{project_id}.{ext}"
        supabase.storage.from_("images").upload(
            path=image_path,
            file=img_bytes,
            file_options={"content-type": content_type, "upsert": "true"},
        )
        supabase.table("projects").update(
            {"image_path": image_path}
        ).eq("id", project_id).execute()

        # Cache locally so the worker can skip the download step.
        os.makedirs("temp", exist_ok=True)
        with open(f"temp/{project_id}_input.{ext}", "wb") as fh:
            fh.write(img_bytes)

    # 3. Enqueue processing job
    job = await redis.enqueue_job(
        "run_process_dots",
        project_id,
        payload.sparsity,
        payload.removeBg,
        payload.erased_points,
    )

    return {"projectId": project_id, "jobId": job.job_id if job else None}


@app.post("/reprocess")
async def reprocess(payload: ReprocessPayload):
    """Re-queues an existing project for dot generation with a new sparsity."""
    redis: ArqRedis = app.state.redis

    supabase.table("projects").update({
        "status": "processing",
        "sparsity": payload.sparsity,
    }).eq("id", payload.projectId).execute()

    job = await redis.enqueue_job(
        "run_process_dots",
        payload.projectId,
        payload.sparsity,
        False,   # removeBg is preserved server-side; no need to re-strip
        [],
    )

    return {"status": "queued", "jobId": job.job_id if job else None}


@app.post("/process")
async def trigger_processing(payload: ProjectPayload):
    """Direct queue trigger (used internally / for testing)."""
    redis: ArqRedis = app.state.redis
    job = await redis.enqueue_job(
        "run_process_dots",
        payload.projectId,
        payload.sparsity,
        payload.removeBg,
        payload.erased_points,
    )
    return {"status": "queued", "job_id": job.job_id if job else None}


@app.delete("/account")
async def delete_account(authorization: str = Header(default="")):
    """Deletes the authenticated user's account, projects, and storage images."""
    user_id = _current_user(authorization)

    # 1. Collect all image paths for this user before deleting rows
    rows = (
        supabase.table("projects")
        .select("image_path")
        .eq("user_id", user_id)
        .execute()
    )
    paths = [r["image_path"] for r in rows.data if r.get("image_path")]

    # 2. Delete images from Storage (best-effort)
    if paths:
        try:
            supabase.storage.from_("images").remove(paths)
        except Exception as e:
            print(f"Storage cleanup warning: {e}")

    # 3. Delete project rows
    supabase.table("projects").delete().eq("user_id", user_id).execute()

    # 4. Delete the auth user
    supabase.auth.admin.delete_user(user_id)

    return {"status": "deleted"}


@app.get("/health")
async def health():
    return {"status": "ok"}
