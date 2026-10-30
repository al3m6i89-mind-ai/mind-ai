"""Start the app: python run.py  ثم افتح http://127.0.0.1:8000"""
import uvicorn

from app import config

if __name__ == "__main__":
    print(f"\n  التطبيق يعمل على: http://{config.HOST}:{config.PORT}\n  App running at:   http://{config.HOST}:{config.PORT}\n")
    uvicorn.run("app.main:app", host=config.HOST, port=config.PORT, log_level="info")
