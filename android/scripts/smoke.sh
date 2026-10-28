#!/usr/bin/env bash
# Installs the dev debug APK on a running emulator, launches it, and fails if the app crashes.
set -u
APK=$(ls app/build/outputs/apk/dev/debug/*.apk | head -1)
PKG=app.nuvola.cloudphone.dev
adb install -r "$APK"
adb logcat -c
adb shell am start -W -n "$PKG/app.nuvola.cloudphone.MainActivity"
sleep 20
adb logcat -d > logcat.txt
adb exec-out screencap -p > screen.png || true
if grep -q "FATAL EXCEPTION" logcat.txt || ! adb shell pidof "$PKG" >/dev/null; then
  echo "App crashed or is not running:"
  grep -A60 "FATAL EXCEPTION" logcat.txt || tail -200 logcat.txt
  exit 1
fi
echo "App is running after 20 seconds."
