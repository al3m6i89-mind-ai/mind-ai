"""Test double for Ollama's HTTP API (/api/tags, /api/chat). Used only by tests: it echoes the question back."""
import asyncio
import json
import sys

from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse

app = FastAPI()
MODEL = "qwen2.5:7b"


@app.get("/api/tags")
def tags():
    return {"models": [{"name": MODEL}]}


@app.post("/api/chat")
async def chat(request: Request):
    body = await request.json()
    last = body["messages"][-1]["content"]
    reply = f"**رد تجريبي من خادم الاختبار.** سؤالك كان:\n\n> {last}\n\n- نقطة أولى\n- نقطة ثانية"

    async def gen():
        for i in range(0, len(reply), 6):
            yield json.dumps({"message": {"role": "assistant", "content": reply[i:i + 6]}, "done": False}) + "\n"
            await asyncio.sleep(0.02)
        yield json.dumps({"message": {"role": "assistant", "content": ""}, "done": True}) + "\n"

    return StreamingResponse(gen(), media_type="application/x-ndjson")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=int(sys.argv[1]) if len(sys.argv) > 1 else 11999, log_level="warning")
