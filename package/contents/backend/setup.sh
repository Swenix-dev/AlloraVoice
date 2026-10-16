#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 SeaQ
# SPDX-License-Identifier: GPL-3.0-or-later
# AlloraVoice – one-time setup (runs in Konsole) / einmalige Einrichtung
set -u
DATA="$HOME/.local/share/alloravoice"
OLD="$HOME/.local/share/voxa"
VENV="$DATA/venv"

# Sprache der Meldungen folgt der Systemsprache (LANGUAGE / LC_ALL / LC_MESSAGES / LANG)
UILANG="${LANGUAGE:-${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}}"
case "$UILANG" in de*) DE=1 ;; *) DE=0 ;; esac
t() { if [ "$DE" = 1 ]; then printf "%s" "$1"; else printf "%s" "$2"; fi; }   # t "Deutsch" "English"

c_ok="\e[32m"; c_info="\e[36m"; c_warn="\e[33m"; c_err="\e[31m"; c_end="\e[0m"
say()  { echo -e "${c_info}▶ $*${c_end}"; }
ok()   { echo -e "${c_ok}✔ $*${c_end}"; }
warn() { echo -e "${c_warn}⚠ $*${c_end}"; }
err()  { echo -e "${c_err}✖ $*${c_end}"; }

echo -e "\n\e[1m  AlloraVoice – $(t "Live-Übersetzung · Einrichtung" "Live translation · Setup")\e[0m\n"

# alte Hintergrunddienste beenden / stop old background services
curl -s -X POST --max-time 1 http://127.0.0.1:47811/quit >/dev/null 2>&1
curl -s -X POST --max-time 1 http://127.0.0.1:47820/quit >/dev/null 2>&1

# 1) Systemwerkzeuge – pactl/parec/pacat stecken in pulseaudio-utils (Arch: libpulse)
if   command -v dnf     >/dev/null; then PM="sudo dnf install -y";                   PULSE="pulseaudio-utils"; VENVPKG=""
elif command -v apt-get >/dev/null; then PM="sudo apt-get install -y";               PULSE="pulseaudio-utils"; VENVPKG="python3-venv"
elif command -v pacman  >/dev/null; then PM="sudo pacman -S --needed --noconfirm";   PULSE="libpulse";         VENVPKG=""
elif command -v zypper  >/dev/null; then PM="sudo zypper --non-interactive install"; PULSE="pulseaudio-utils"; VENVPKG=""
else PM=""; PULSE="pulseaudio-utils"; VENVPKG=""; fi
NEED=()
command -v pactl >/dev/null || NEED+=("$PULSE")
command -v parec >/dev/null || NEED+=("$PULSE")
command -v pacat >/dev/null || NEED+=("$PULSE")
command -v curl  >/dev/null || NEED+=("curl")
if [ -n "$VENVPKG" ] && ! python3 -c "import ensurepip" 2>/dev/null; then NEED+=("$VENVPKG"); fi
if [ ${#NEED[@]} -gt 0 ]; then
    PKGS=$(printf "%s\n" "${NEED[@]}" | sort -u | tr '\n' ' ')
    if [ -z "$PM" ]; then
        err "$(t "Bitte diese Pakete selbst installieren:" "Please install these packages yourself:") $PKGS"; exit 1
    fi
    say "$(t "Installiere Systempakete:" "Installing system packages:") $PKGS $(t "(Passwort wird abgefragt)" "(you will be asked for your password)")"
    $PM $PKGS || { err "$(t "Paketinstallation fehlgeschlagen" "Package installation failed")"; exit 1; }
fi
ok "$(t "Systemwerkzeuge vorhanden" "System tools available")"

# 2) vorhandene Voxa-Einrichtung übernehmen / reuse an existing Voxa setup
mkdir -p "$DATA"
if [ ! -x "$VENV/bin/python" ] && [ -x "$OLD/venv/bin/python" ]; then
    say "$(t "Übernehme vorhandene Einrichtung von Voxa …" "Reusing the existing Voxa setup …")"
    mv "$OLD/venv" "$VENV"
fi

# 3) Python wählen – Whisper hat für sehr neue Python-Versionen evtl. noch keine Pakete
if [ ! -x "$VENV/bin/python" ]; then
    PY=""
    for cand in python3.12 python3.13 python3.11 python3; do
        if command -v "$cand" >/dev/null; then PY="$cand"; break; fi
    done
    [ -z "$PY" ] && { err "$(t "Kein Python gefunden – bitte python3 installieren" "No Python found – please install python3")"; exit 1; }
    say "$(t "Erstelle Python-Umgebung mit" "Creating Python environment with") $($PY --version) …"
    "$PY" -m venv "$VENV" || { err "$(t "Python-Umgebung konnte nicht erstellt werden (Paket python3-venv / python3-virtualenv?)" "Could not create the Python environment (package python3-venv / python3-virtualenv?)")"; exit 1; }
fi
PIP=("$VENV/bin/python" -m pip)
"${PIP[@]}" install --upgrade pip -q

say "$(t "Installiere Stimmen, Übersetzer, Online-Erkennung …" "Installing voices, translator, online recognition …")"
"${PIP[@]}" install -q --upgrade numpy edge-tts deep-translator SpeechRecognition av dbus-next \
    || { err "$(t "Installation fehlgeschlagen" "Installation failed")"; exit 1; }
ok "$(t "Grundpakete installiert" "Base packages installed")"

say "$(t "Installiere Whisper (lokale Spracherkennung) …" "Installing Whisper (local speech recognition) …")"
if "${PIP[@]}" install -q faster-whisper; then
    ok "$(t "Whisper installiert" "Whisper installed")"
    say "$(t "Lade Sprachmodelle vor (einmalig, ca. 300 MB) …" "Downloading speech models (one time, about 300 MB) …")"
    "$VENV/bin/python" - <<'EOF'
from faster_whisper import WhisperModel
for name in ("base.en", "base"):   # base.en = English, base = all other languages
    print("   model", name, "…", flush=True)
    WhisperModel(name, device="cpu", compute_type="int8")
EOF
    ok "$(t "Modelle bereit" "Models ready")"
else
    warn "$(t "Whisper konnte nicht installiert werden." "Whisper could not be installed.")"
    warn "$(t "Tipp: Python 3.12 installieren, ~/.local/share/alloravoice löschen und erneut einrichten." "Tip: install Python 3.12, delete ~/.local/share/alloravoice and run the setup again.")"
    warn "$(t "Bis dahin im Widget „Google Online“ als Erkennung wählen." "Until then, choose “Google Online” as recognition in the widget.")"
fi

# 4) Stimme testen / test a neural voice
say "$(t "Teste Microsoft-Neural-Stimme …" "Testing Microsoft neural voice …")"
"$VENV/bin/python" - <<'EOF'
import asyncio, edge_tts
async def t():
    n = 0
    async for c in edge_tts.Communicate("Test", "en-US-AvaMultilingualNeural").stream():
        if c["type"] == "audio": n += len(c["data"])
    return n
print("   audio bytes:", asyncio.run(t()))
EOF

echo
ok "$(t "Fertig! Du kannst dieses Fenster schließen und im Widget den Schalter einschalten." "Done! You can close this window and switch on translation in the widget.")"
