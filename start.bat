@echo off
chcp 65001 >nul
rem تشغيل التطبيق على Windows. أول تشغيل يثبّت المكتبات تلقائياً.
cd /d "%~dp0"
if not exist .venv (
  echo Creating Python environment...
  py -3 -m venv .venv 2>nul || python -m venv .venv
)
.venv\Scripts\python -m pip install -q --upgrade pip
.venv\Scripts\python -m pip install -q -r requirements.txt
if not exist .env copy .env.example .env >nul
start "" http://127.0.0.1:8000
.venv\Scripts\python run.py
pause
