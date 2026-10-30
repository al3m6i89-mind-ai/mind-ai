import asyncio
import json
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from . import ai, config, db, files

DEFAULT_TITLE = "محادثة جديدة"
STATIC_DIR = config.BASE_DIR / "static"

@asynccontextmanager
async def lifespan(_app):
    db.init()
    yield


app = FastAPI(title="File Chat", docs_url=None, redoc_url=None, lifespan=lifespan)


@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; img-src 'self' blob: data:; style-src 'self' 'unsafe-inline'; "
        "script-src 'self'; connect-src 'self'; frame-ancestors 'none'"
    )
    return response


def error(status: int, code: str, message: str) -> HTTPException:
    return HTTPException(status_code=status, detail={"code": code, "message": message})


# ---------- serializers ----------

def attachment_out(row) -> dict:
    return {
        "id": row["id"],
        "message_id": row["message_id"],
        "name": row["original_name"],
        "ext": row["ext"],
        "kind": row["kind"],
        "type_label": files.SUPPORTED[row["ext"]][2],
        "size": row["size"],
        "status": row["status"],
        "url": f"/api/attachments/{row['id']}/file",
        "created_at": row["created_at"],
    }


def message_out(row, attachments: list[dict]) -> dict:
    return {
        "id": row["id"],
        "role": row["role"],
        "content": row["content"],
        "status": row["status"],
        "error": json.loads(row["error"]) if row["error"] else None,
        "model": row["model"],
        "created_at": row["created_at"],
        "attachments": attachments,
    }


def get_conversation(conn, conversation_id: str):
    row = conn.execute("SELECT * FROM conversations WHERE id = ?", (conversation_id,)).fetchone()
    if row is None:
        raise error(404, "not_found", "Conversation not found.")
    return row


# ---------- health ----------

@app.get("/api/health")
async def health():
    return {"ok": True, "ai": await ai.status(), "max_upload_mb": config.MAX_UPLOAD_MB,
            "supported": sorted(files.SUPPORTED)}


# ---------- conversations ----------

class ConversationIn(BaseModel):
    title: str | None = Field(default=None, max_length=200)


class ConversationPatch(BaseModel):
    title: str = Field(min_length=1, max_length=200)


@app.get("/api/conversations")
def list_conversations(q: str = ""):
    q = q.strip()
    with db.connect() as conn:
        if q:
            like = f"%{q}%"
            rows = conn.execute(
                """SELECT c.*, (SELECT COUNT(*) FROM messages m WHERE m.conversation_id = c.id) AS n
                   FROM conversations c
                   WHERE c.title LIKE ? OR EXISTS (
                       SELECT 1 FROM messages m WHERE m.conversation_id = c.id AND m.content LIKE ?)
                      OR EXISTS (
                       SELECT 1 FROM attachments a WHERE a.conversation_id = c.id AND a.original_name LIKE ?)
                   ORDER BY c.updated_at DESC""",
                (like, like, like),
            ).fetchall()
        else:
            rows = conn.execute(
                """SELECT c.*, (SELECT COUNT(*) FROM messages m WHERE m.conversation_id = c.id) AS n
                   FROM conversations c ORDER BY c.updated_at DESC"""
            ).fetchall()
    return [{"id": r["id"], "title": r["title"], "updated_at": r["updated_at"], "message_count": r["n"]}
            for r in rows]


@app.post("/api/conversations", status_code=201)
def create_conversation(body: ConversationIn):
    cid, ts = db.new_id(), db.now()
    title = (body.title or "").strip() or DEFAULT_TITLE
    with db.connect() as conn:
        conn.execute("INSERT INTO conversations VALUES (?, ?, ?, ?)", (cid, title, ts, ts))
    return {"id": cid, "title": title, "updated_at": ts, "message_count": 0}


@app.patch("/api/conversations/{conversation_id}")
def rename_conversation(conversation_id: str, body: ConversationPatch):
    title = body.title.strip()
    if not title:
        raise error(422, "empty_title", "Title cannot be empty.")
    with db.connect() as conn:
        get_conversation(conn, conversation_id)
        conn.execute("UPDATE conversations SET title = ? WHERE id = ?", (title, conversation_id))
    return {"id": conversation_id, "title": title}


@app.delete("/api/conversations/{conversation_id}", status_code=204)
def delete_conversation(conversation_id: str):
    with db.connect() as conn:
        get_conversation(conn, conversation_id)
        paths = [r["stored_path"] for r in conn.execute(
            "SELECT stored_path FROM attachments WHERE conversation_id = ?", (conversation_id,))]
        conn.execute("DELETE FROM conversations WHERE id = ?", (conversation_id,))
    for p in paths:
        Path(p).unlink(missing_ok=True)
    conv_dir = config.UPLOAD_DIR / conversation_id
    if conv_dir.exists() and not any(conv_dir.iterdir()):
        conv_dir.rmdir()


@app.get("/api/conversations/{conversation_id}/messages")
def list_messages(conversation_id: str):
    with db.connect() as conn:
        conv = get_conversation(conn, conversation_id)
        msgs = conn.execute(
            "SELECT * FROM messages WHERE conversation_id = ? ORDER BY created_at", (conversation_id,)
        ).fetchall()
        atts = conn.execute(
            "SELECT * FROM attachments WHERE conversation_id = ? ORDER BY created_at", (conversation_id,)
        ).fetchall()
    by_msg: dict[str, list] = {}
    pending = []
    for a in atts:
        if a["message_id"]:
            by_msg.setdefault(a["message_id"], []).append(attachment_out(a))
        else:
            pending.append(attachment_out(a))
    return {
        "conversation": {"id": conv["id"], "title": conv["title"]},
        "messages": [message_out(m, by_msg.get(m["id"], [])) for m in msgs],
        "pending_attachments": pending,
    }


# ---------- attachments ----------

@app.post("/api/conversations/{conversation_id}/attachments", status_code=201)
async def upload_attachment(conversation_id: str, file: UploadFile = File(...)):
    with db.connect() as conn:
        get_conversation(conn, conversation_id)
    name = Path(file.filename or "file").name[:255]
    data = await file.read(config.MAX_UPLOAD_BYTES + 1)
    if len(data) > config.MAX_UPLOAD_BYTES:
        raise error(413, "too_large", f"File is larger than {config.MAX_UPLOAD_MB} MB.")
    try:
        ext, kind, mime = files.validate(name, data)
    except files.UploadRejected as exc:
        raise error(415, exc.code, exc.message)

    aid = db.new_id()
    conv_dir = config.UPLOAD_DIR / conversation_id
    conv_dir.mkdir(parents=True, exist_ok=True)
    stored = conv_dir / f"{aid}.{ext}"
    stored.write_bytes(data)
    with db.connect() as conn:
        conn.execute(
            "INSERT INTO attachments VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?)",
            (aid, conversation_id, name, ext, kind, mime, len(data), str(stored), "uploaded", db.now()),
        )
        row = conn.execute("SELECT * FROM attachments WHERE id = ?", (aid,)).fetchone()
    return attachment_out(row)


@app.get("/api/attachments/{attachment_id}/file")
def download_attachment(attachment_id: str, download: bool = False):
    with db.connect() as conn:
        row = conn.execute("SELECT * FROM attachments WHERE id = ?", (attachment_id,)).fetchone()
    if row is None or not Path(row["stored_path"]).exists():
        raise error(404, "not_found", "Attachment not found.")
    inline = not download and (row["kind"] == "image" or row["ext"] in ("pdf", "txt", "md", "markdown", "csv"))
    return FileResponse(
        row["stored_path"],
        media_type=row["mime"],
        filename=row["original_name"],
        content_disposition_type="inline" if inline else "attachment",
    )


@app.delete("/api/attachments/{attachment_id}", status_code=204)
def delete_attachment(attachment_id: str):
    with db.connect() as conn:
        row = conn.execute("SELECT * FROM attachments WHERE id = ?", (attachment_id,)).fetchone()
        if row is None:
            raise error(404, "not_found", "Attachment not found.")
        conn.execute("DELETE FROM attachments WHERE id = ?", (attachment_id,))
    Path(row["stored_path"]).unlink(missing_ok=True)


# ---------- messages + streaming ----------

class MessageIn(BaseModel):
    content: str = Field(default="", max_length=20000)
    attachment_ids: list[str] = Field(default_factory=list, max_length=20)


def sse(event: str, data) -> str:
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


def build_history(conn, conversation_id: str) -> list[dict]:
    rows = conn.execute(
        """SELECT * FROM messages WHERE conversation_id = ? AND (role = 'user' OR status = 'complete')
           ORDER BY created_at DESC LIMIT ?""",
        (conversation_id, config.HISTORY_MESSAGES),
    ).fetchall()[::-1]
    history = []
    for m in rows:
        content = m["content"]
        if m["role"] == "user":
            atts = conn.execute(
                "SELECT original_name, ext FROM attachments WHERE message_id = ?", (m["id"],)).fetchall()
            if atts:
                listing = ", ".join(f"{a['original_name']} ({files.SUPPORTED[a['ext']][2]})" for a in atts)
                content = f"{content}\n\n[Attached, contents not available yet: {listing}]".strip()
        if history and history[-1]["role"] == m["role"]:
            history[-1]["content"] += "\n\n" + content
        else:
            history.append({"role": m["role"], "content": content})
    while history and history[0]["role"] != "user":
        history.pop(0)
    return history


async def generate(conversation_id: str, request: Request, first_events: list[str]):
    with db.connect() as conn:
        history = build_history(conn, conversation_id)
    assistant_id = db.new_id()
    parts: list[str] = []
    status, err = "complete", None
    try:
        for e in first_events:
            yield e
        yield sse("start", {"id": assistant_id, "model": ai.model_name()})
        if not history:
            raise ai.AIError("empty_history", "Nothing to answer.")
        async for chunk in ai.stream_reply(history):
            parts.append(chunk)
            yield sse("delta", {"text": chunk})
            if await request.is_disconnected():
                status = "stopped"
                break
    except ai.AIError as exc:
        status, err = "error", {"code": exc.code, "message": exc.message}
    except asyncio.CancelledError:
        status = "stopped"
        raise
    except Exception as exc:  # surface unexpected failures instead of hiding them
        status, err = "error", {"code": "internal_error", "message": str(exc)}
    finally:
        # Saved even when the client disconnects, so a stopped reply keeps its partial text.
        row = save_assistant(assistant_id, conversation_id, "".join(parts), status, err)
    yield sse("error" if status == "error" else "done", message_out(row, []))


def save_assistant(assistant_id: str, conversation_id: str, content: str, status: str, err):
    ts = db.now()
    with db.connect() as conn:
        conn.execute(
            "INSERT INTO messages VALUES (?, ?, 'assistant', ?, ?, ?, ?, ?)",
            (assistant_id, conversation_id, content, status,
             json.dumps(err, ensure_ascii=False) if err else None, ai.model_name(), ts),
        )
        conn.execute("UPDATE conversations SET updated_at = ? WHERE id = ?", (ts, conversation_id))
        return conn.execute("SELECT * FROM messages WHERE id = ?", (assistant_id,)).fetchone()


STREAM_HEADERS = {"Cache-Control": "no-cache", "X-Accel-Buffering": "no"}


@app.post("/api/conversations/{conversation_id}/messages")
async def send_message(conversation_id: str, body: MessageIn, request: Request):
    content = body.content.strip()
    if not content and not body.attachment_ids:
        raise error(422, "empty_message", "Write a message or attach a file.")
    with db.connect() as conn:
        conv = get_conversation(conn, conversation_id)
        atts = []
        for aid in body.attachment_ids:
            a = conn.execute(
                "SELECT * FROM attachments WHERE id = ? AND conversation_id = ? AND message_id IS NULL",
                (aid, conversation_id),
            ).fetchone()
            if a is None:
                raise error(422, "bad_attachment", "An attachment was not found in this conversation.")
            atts.append(a)
        mid, ts = db.new_id(), db.now()
        conn.execute("INSERT INTO messages VALUES (?, ?, 'user', ?, 'complete', NULL, NULL, ?)",
                     (mid, conversation_id, content, ts))
        for a in atts:
            conn.execute("UPDATE attachments SET message_id = ? WHERE id = ?", (mid, a["id"]))
        title = conv["title"]
        if title == DEFAULT_TITLE:
            source = content or atts[0]["original_name"]
            title = " ".join(source.split())[:60]
            conn.execute("UPDATE conversations SET title = ? WHERE id = ?", (title, conversation_id))
        conn.execute("UPDATE conversations SET updated_at = ? WHERE id = ?", (ts, conversation_id))
        user_row = conn.execute("SELECT * FROM messages WHERE id = ?", (mid,)).fetchone()
        user_atts = [attachment_out(r) for r in conn.execute(
            "SELECT * FROM attachments WHERE message_id = ? ORDER BY created_at", (mid,))]
    first = [sse("user", {"message": message_out(user_row, user_atts), "title": title})]
    return StreamingResponse(generate(conversation_id, request, first),
                             media_type="text/event-stream", headers=STREAM_HEADERS)


@app.post("/api/conversations/{conversation_id}/regenerate")
async def regenerate(conversation_id: str, request: Request):
    """Retry: drop the trailing assistant reply (failed or not) and answer the last user message again."""
    with db.connect() as conn:
        get_conversation(conn, conversation_id)
        last = conn.execute(
            "SELECT * FROM messages WHERE conversation_id = ? ORDER BY created_at DESC LIMIT 1",
            (conversation_id,)).fetchone()
        if last is None:
            raise error(422, "empty_history", "Nothing to retry.")
        if last["role"] == "assistant":
            conn.execute("DELETE FROM messages WHERE id = ?", (last["id"],))
    return StreamingResponse(generate(conversation_id, request, [sse("retry", {"removed": last["id"]})]),
                             media_type="text/event-stream", headers=STREAM_HEADERS)


@app.exception_handler(HTTPException)
async def http_error_handler(_request: Request, exc: HTTPException):
    detail = exc.detail if isinstance(exc.detail, dict) else {"code": "error", "message": str(exc.detail)}
    return JSONResponse(status_code=exc.status_code, content={"error": detail})


@app.get("/")
def index():
    return FileResponse(STATIC_DIR / "index.html", headers={"Cache-Control": "no-cache"})


app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
