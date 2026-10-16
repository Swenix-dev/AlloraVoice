#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 SeaQ
# SPDX-License-Identifier: GPL-3.0-or-later
# Startet das AlloraVoice-Backend im Hintergrund (wird vom Widget aufgerufen)
DIR="$(cd "$(dirname "$0")" && pwd)"
DATA="$HOME/.local/share/alloravoice"
OLD="$HOME/.local/share/voxa"
PY="$DATA/venv/bin/python"

# Einrichtung der alten Voxa-Version übernehmen, statt alles neu zu laden
if [ ! -x "$PY" ] && [ -x "$OLD/venv/bin/python" ]; then
    mkdir -p "$DATA"
    mv "$OLD/venv" "$DATA/venv"
fi

if [ ! -x "$PY" ]; then
    echo "notinstalled"
    exit 1
fi
if curl -s --max-time 1 http://127.0.0.1:47820/ping >/dev/null 2>&1; then
    echo "running"
    exit 0
fi
mkdir -p "$DATA"
# seit 2.1: Spul-Erkennung braucht dbus-next (klein, wird bei Bedarf nachinstalliert)
"$PY" -c "import dbus_next" 2>/dev/null || "$PY" -m pip install -q dbus-next >>"$DATA/backend.log" 2>&1
setsid nohup "$PY" "$DIR/alloravoice_backend.py" >"$DATA/backend.log" 2>&1 < /dev/null &
echo "started"
