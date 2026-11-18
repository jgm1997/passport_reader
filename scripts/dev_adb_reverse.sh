#!/usr/bin/env bash
# Everything the phone needs before `flutter run`. Safe to run repeatedly.
set -euo pipefail
adb reverse tcp:8000 tcp:8000
adb reverse --list