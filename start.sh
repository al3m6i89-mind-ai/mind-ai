#!/usr/bin/env bash
# تشغيل التطبيق على Mac/Linux. أول تشغيل يثبّت المكتبات تلقائياً.
set -e
cd "$(dirname "$0")"
if [ ! -d .venv ]; then
  echo "إنشاء بيئة Python..."
  python3 -m venv .venv
fi
.venv/bin/pip install -q --upgrade pip
.venv/bin/pip install -q -r requirements.txt
[ -f .env ] || cp .env.example .env
.venv/bin/python run.py
