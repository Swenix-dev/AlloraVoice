#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 SeaQ
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Adds a natural voice-over to the intro video using Microsoft neural voices
# (the same engine AlloraVoice uses). Needs: ffmpeg, internet, python3 + edge-tts.
#
#   ./add-narration.sh                                  # default voice: Ava (US)
#   ./add-narration.sh en-US-AndrewMultilingualNeural   # any other voice
#
# Result: alloravoice-intro-narrated.mp4
set -euo pipefail
cd "$(dirname "$0")"
VOICE="${1:-en-US-AvaMultilingualNeural}"

PY=python3
if [ -x "$HOME/.local/share/alloravoice/venv/bin/python" ]; then
    PY="$HOME/.local/share/alloravoice/venv/bin/python"   # reuse AlloraVoice's environment
fi
if ! "$PY" -c "import edge_tts" 2>/dev/null; then
    echo "edge-tts not found – installing into a temporary venv …"
    python3 -m venv .narration/venv && .narration/venv/bin/pip install -q edge-tts
    PY=.narration/venv/bin/python
fi
command -v ffmpeg >/dev/null || { echo "Please install ffmpeg first."; exit 1; }

mkdir -p .narration
"$PY" - "$VOICE" <<'EOF'
import asyncio, json, subprocess, sys
import edge_tts

voice = sys.argv[1]
scenes = json.load(open("narration.en.json"))

def length(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "csv=p=0", path], capture_output=True, text=True).stdout
    return float(out.strip() or 0)

async def main():
    inputs, filters = ["-i", "alloravoice-intro.mp4"], []
    for i, s in enumerate(scenes):
        raw = f".narration/{i}.mp3"
        await edge_tts.Communicate(s["text"], voice).save(raw)
        room = s["duration"] - 0.8                 # leave a little air before the next scene
        speed = max(1.0, length(raw) / room)       # only speed up if it would not fit
        print(f"scene {i + 1}: {length(raw):.1f}s of speech, {room:.1f}s available"
              + (f" → tempo {speed:.2f}×" if speed > 1 else ""))
        inputs += ["-i", raw]
        delay = int((s["start"] + 0.4) * 1000)
        filters.append(f"[{i + 1}:a]atempo={speed:.3f},adelay={delay}|{delay}[a{i}]")
    mix = "".join(f"[a{i}]" for i in range(len(scenes)))
    filters.append(f"{mix}amix=inputs={len(scenes)}:normalize=0,volume=1.0[aout]")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *inputs,
                    "-filter_complex", ";".join(filters),
                    "-map", "0:v", "-map", "[aout]", "-c:v", "copy", "-c:a", "aac", "-b:a", "160k",
                    "-shortest", "alloravoice-intro-narrated.mp4"], check=True)

asyncio.run(main())
EOF
echo "✔ alloravoice-intro-narrated.mp4"
