import io
import json
import os
import socket
import subprocess
import sys
import time
import zipfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


def free_port() -> int:
    s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close(); return port


@pytest.fixture()
def client(tmp_path, monkeypatch):
    port = free_port()
    proc = subprocess.Popen([sys.executable, str(ROOT / "tests" / "fake_ollama.py"), str(port)])
    for _ in range(50):
        try:
            socket.create_connection(("127.0.0.1", port), 0.2).close(); break
        except OSError:
            time.sleep(0.1)
    monkeypatch.setenv("DATA_DIR", str(tmp_path))
    monkeypatch.setenv("OLLAMA_URL", f"http://127.0.0.1:{port}")
    monkeypatch.setenv("AI_PROVIDER", "ollama")
    monkeypatch.setenv("MAX_UPLOAD_MB", "1")
    for mod in [m for m in sys.modules if m == "app" or m.startswith("app.")]:
        del sys.modules[mod]
    sys.path.insert(0, str(ROOT))
    from fastapi.testclient import TestClient
    from app.main import app
    with TestClient(app) as c:
        c.ollama_port = port
        yield c
    proc.terminate()


def parse_sse(text: str):
    events = []
    for block in text.strip().split("\n\n"):
        ev = data = None
        for line in block.split("\n"):
            if line.startswith("event:"): ev = line[6:].strip()
            if line.startswith("data:"): data = json.loads(line[5:].strip())
        events.append((ev, data))
    return events


def docx_bytes() -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("[Content_Types].xml", "<Types/>")
        z.writestr("word/document.xml", "<w:document/>")
    return buf.getvalue()


PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64


def test_health_reports_model(client):
    r = client.get("/api/health").json()
    assert r["ai"]["available"] is True and r["ai"]["provider"] == "ollama"


def test_conversation_crud_and_search(client):
    c = client.post("/api/conversations", json={}).json()
    assert c["title"] == "محادثة جديدة"
    assert client.patch(f"/api/conversations/{c['id']}", json={"title": "تحليل عقد العمل"}).status_code == 200
    assert client.get("/api/conversations", params={"q": "عقد"}).json()[0]["id"] == c["id"]
    assert client.get("/api/conversations", params={"q": "غير موجود"}).json() == []
    assert client.patch(f"/api/conversations/{c['id']}", json={"title": "   "}).status_code == 422
    assert client.delete(f"/api/conversations/{c['id']}").status_code == 204
    assert client.get(f"/api/conversations/{c['id']}/messages").status_code == 404


def test_chat_streams_and_persists(client):
    cid = client.post("/api/conversations", json={}).json()["id"]
    r = client.post(f"/api/conversations/{cid}/messages", json={"content": "مرحبا، كيف حالك؟"})
    events = parse_sse(r.text)
    kinds = [e for e, _ in events]
    assert kinds[0] == "user" and kinds[1] == "start" and kinds[-1] == "done" and "delta" in kinds
    assert events[0][1]["title"] == "مرحبا، كيف حالك؟"
    final = events[-1][1]
    assert final["status"] == "complete" and "مرحبا، كيف حالك؟" in final["content"]
    msgs = client.get(f"/api/conversations/{cid}/messages").json()["messages"]
    assert [m["role"] for m in msgs] == ["user", "assistant"]
    # searching message content finds the conversation
    assert client.get("/api/conversations", params={"q": "كيف حالك"}).json()[0]["id"] == cid


def test_error_is_reported_and_retry_works(client, monkeypatch):
    from app import config
    cid = client.post("/api/conversations", json={}).json()["id"]
    monkeypatch.setattr(config, "OLLAMA_URL", "http://127.0.0.1:1")
    events = parse_sse(client.post(f"/api/conversations/{cid}/messages", json={"content": "سؤال"}).text)
    assert events[-1][0] == "error" and events[-1][1]["error"]["code"] == "ollama_not_running"
    assert client.get("/api/health").json()["ai"]["reason"] == "ollama_not_running"
    monkeypatch.setattr(config, "OLLAMA_URL", f"http://127.0.0.1:{client.ollama_port}")
    events = parse_sse(client.post(f"/api/conversations/{cid}/regenerate").text)
    assert events[-1][0] == "done"
    msgs = client.get(f"/api/conversations/{cid}/messages").json()["messages"]
    assert [m["status"] for m in msgs] == ["complete", "complete"]


def test_upload_validation(client):
    cid = client.post("/api/conversations", json={}).json()["id"]
    up = lambda name, data: client.post(f"/api/conversations/{cid}/attachments", files={"file": (name, data)})
    ok = up("عقد العمل.pdf", b"%PDF-1.7\n...")
    assert ok.status_code == 201 and ok.json()["type_label"] == "PDF" and ok.json()["status"] == "uploaded"
    assert up("report.docx", docx_bytes()).status_code == 201
    assert up("photo.png", PNG).status_code == 201
    assert up("notes.txt", "نص عربي".encode()).status_code == 201
    assert up("virus.exe", b"MZ...").json()["error"]["code"] == "unsupported_type"
    assert up("fake.pdf", b"MZ not a pdf").json()["error"]["code"] == "content_mismatch"
    assert up("fake.docx", b"PK\x03\x04garbage").json()["error"]["code"] == "content_mismatch"
    assert up("fake.png", b"GIF89a").json()["error"]["code"] == "content_mismatch"
    assert up("empty.txt", b"").json()["error"]["code"] == "empty_file"
    assert up("big.txt", b"a" * (1024 * 1024 + 10)).json()["error"]["code"] == "too_large"


def test_attachment_flow_open_and_delete(client):
    cid = client.post("/api/conversations", json={}).json()["id"]
    att = client.post(f"/api/conversations/{cid}/attachments",
                      files={"file": ("فاتورة.png", PNG)}).json()
    pending = client.get(f"/api/conversations/{cid}/messages").json()["pending_attachments"]
    assert [a["id"] for a in pending] == [att["id"]]
    events = parse_sse(client.post(f"/api/conversations/{cid}/messages",
                                   json={"content": "كم إجمالي الفاتورة؟", "attachment_ids": [att["id"]]}).text)
    assert events[0][1]["message"]["attachments"][0]["name"] == "فاتورة.png"
    # the model is told the attachment exists but its contents are not available yet
    assert "contents not available yet" in events[-1][1]["content"]
    f = client.get(att["url"])
    assert f.status_code == 200 and f.content == PNG and f.headers["content-type"] == "image/png"
    assert f.headers["x-content-type-options"] == "nosniff"
    # an attachment cannot be reused in another message
    assert client.post(f"/api/conversations/{cid}/messages",
                       json={"content": "x", "attachment_ids": [att["id"]]}).status_code == 422
    assert client.delete(f"/api/attachments/{att['id']}").status_code == 204
    assert client.get(att["url"]).status_code == 404


def test_delete_conversation_removes_files(client, tmp_path):
    cid = client.post("/api/conversations", json={}).json()["id"]
    client.post(f"/api/conversations/{cid}/attachments", files={"file": ("a.pdf", b"%PDF-1.4")})
    assert any((tmp_path / "uploads" / cid).iterdir())
    client.delete(f"/api/conversations/{cid}")
    assert not (tmp_path / "uploads" / cid).exists()


def test_attachments_are_scoped_to_conversation(client):
    a = client.post("/api/conversations", json={}).json()["id"]
    b = client.post("/api/conversations", json={}).json()["id"]
    att = client.post(f"/api/conversations/{a}/attachments", files={"file": ("a.pdf", b"%PDF-1.4")}).json()
    r = client.post(f"/api/conversations/{b}/messages", json={"content": "x", "attachment_ids": [att["id"]]})
    assert r.status_code == 422
    assert client.get(f"/api/conversations/{b}/messages").json()["pending_attachments"] == []


def test_empty_message_rejected(client):
    cid = client.post("/api/conversations", json={}).json()["id"]
    assert client.post(f"/api/conversations/{cid}/messages", json={"content": "  "}).status_code == 422
