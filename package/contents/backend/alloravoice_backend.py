#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 SeaQ
# SPDX-License-Identifier: GPL-3.0-or-later
"""
AlloraVoice – Live-Übersetzung (Backend)

Greift den gesamten Systemton über PipeWire ab, erkennt die gesprochene Sprache,
übersetzt sie in die Zielsprache und liest sie mit natürlicher Neural-Stimme vor.

Audio-Routing (ohne Rückkopplung):
  Apps ──► [alloravoice_capture (virtuelle Senke)] ──monitor──► Erkennung
                         └──loopback (Lautstärke = Original/Ducking)──► Lautsprecher
  AlloraVoice-Stimme (pacat, gestreamt) ──────────────────────────────► Lautsprecher

Mitspringen: Über die Medien-Schnittstelle (MPRIS – dieselbe, die KDEs Medien-
steuerung nutzt) erkennt AlloraVoice Vor-/Zurückspulen und Pause in YouTube,
Udemy, VLC usw. Dann wird alles Alte sofort verworfen und die Stimme setzt an
der neuen Stelle neu an.

Tempo-Regelung: Die Stimme wird nie mitten im Satz abgebrochen. Stattdessen wird
(1) das Sprechtempo jeder Ansage vorausschauend so gewählt, dass sie in die Zeit des
Originals passt, und (2) die Wiedergabe stufenlos beschleunigt (bis 1,35×, ohne
Tonhöhen-Änderung), sobald sich Ansagen stauen. Wartende Sätze werden zusammengefasst
statt verworfen. Nur bei extremem Rückstand wird zwischen zwei Ansagen gesprungen.

Steuerung per HTTP auf 127.0.0.1:47820 (wird vom Plasma-Widget benutzt).
"""
import asyncio
import json
import os
import queue
import signal
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np

VERSION = "2.5.0"
PORT = 47820
OLD_PORTS = (47811,)
SR = 16000
FRAME = 480  # 30 ms bei 16 kHz
TTS_SR = 24000
CAPTURE_SINK = "alloravoice_capture"
STALE_SINKS = ("alloravoice_capture", "voxa_capture")
DATA_DIR = os.path.expanduser("~/.local/share/alloravoice")
STATE_FILE = os.path.join(DATA_DIR, "routing.json")
TTS_APP_NAME = "AlloraVoiceTTS"

LANG_EN = {"code": "en", "whisper": "en", "stt": "en-US", "google": "en", "deepl": "EN-US",
           "deeplSource": "EN", "fallback": {"female": "en-US-JennyNeural", "male": "en-US-GuyNeural"}}
LANG_DE = {"code": "de", "whisper": "de", "stt": "de-DE", "google": "de", "deepl": "DE",
           "deeplSource": "DE", "fallback": {"female": "de-DE-KatjaNeural", "male": "de-DE-ConradNeural"}}

RESPONSIVENESS = {
    #            Stille bis Satzende, maximale Segmentlänge (Sekunden)
    "fast":     (0.25, 3.5),
    "balanced": (0.35, 5.0),
    "precise":  (0.60, 9.0),
}

JUNK = {"you", "thank you.", "thanks for watching!", "thank you for watching.", "bye.", ".",
        "thanks.", "thank you very much.", "subtitles by the amara.org community",
        "untertitel im auftrag des zdf, 2017", "untertitel der amara.org-community", "vielen dank."}

DEFAULT_CFG = {
    "voice": "de-DE-SeraphinaMultilingualNeural",
    "gender": "female",
    "rate": 0,              # % Sprechtempo (Grundwert)
    "pitch": 0,             # Hz Tonhöhe
    "ttsVolume": 100,       # %
    "originalVolume": 100,  # % Lautstärke des Originals
    "duck": True,           # Original beim Sprechen absenken
    "duckLevel": 20,        # % während die Stimme spricht
    "adaptiveTempo": True,  # Tempo an Länge des Originals anpassen
    "syncMode": True,       # bei Rückstand zur aktuellen Stelle springen
    "maxLag": 8,            # Sekunden reiner Rückstand, ab dem im Notfall gesprungen wird
    "mediaSync": True,      # auf Vorspulen / Pause im Player reagieren
    "recognizer": "whisper-base",  # whisper-tiny | whisper-base | whisper-small | google
    "responsiveness": "balanced",
    "translator": "google",        # google | deepl
    "deeplKey": "",
    "source": LANG_EN,             # {"code": "auto"} = automatisch erkennen
    "target": LANG_DE,
    "minLevel": 3,                 # Empfindlichkeit (1–10)
}


class AVError(RuntimeError):
    """Fehler mit Code – das Widget übersetzt ihn in die Systemsprache."""

    def __init__(self, code, message, arg=""):
        super().__init__(message)
        self.code, self.arg = code, arg


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, file=sys.stderr, flush=True)


def run(cmd, check=False):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if check and r.returncode != 0:
            raise RuntimeError(f"{' '.join(cmd)}: {r.stderr.strip()}")
        return r.stdout.strip()
    except FileNotFoundError:
        raise AVError("missing_program", f"Missing program: {cmd[0]}", cmd[0])


def src_code(cfg):
    return (cfg.get("source") or LANG_EN).get("code", "en")


# ─────────────────────────────── Audio-Routing ───────────────────────────────
class Router:
    def __init__(self):
        self.real_sink = None
        self.null_mod = None
        self.loop_mod = None
        self.own_pids = set()
        self.lock = threading.Lock()
        self.current_volume = 100

    @staticmethod
    def _json(kind):
        out = run(["pactl", "-f", "json", "list", kind])
        try:
            return json.loads(out) if out else []
        except json.JSONDecodeError:
            return []

    def cleanup_stale(self):
        """Reste eines abgestürzten Laufs (auch der alten Voxa-Version) entfernen."""
        stale_default = run(["pactl", "get-default-sink"]) in STALE_SINKS
        for line in run(["pactl", "list", "short", "modules"]).splitlines():
            parts = line.split("\t")
            if len(parts) >= 3 and any(s in parts[2] for s in STALE_SINKS):
                run(["pactl", "unload-module", parts[0]])
        for state in (STATE_FILE, os.path.expanduser("~/.local/share/voxa/routing.json")):
            if os.path.exists(state):
                try:
                    with open(state) as f:
                        old = json.load(f).get("real_sink")
                    if old and (stale_default or run(["pactl", "get-default-sink"]) == ""):
                        run(["pactl", "set-default-sink", old])
                    os.remove(state)
                except Exception:
                    pass

    def start(self):
        with self.lock:
            self.cleanup_stale()
            sink = run(["pactl", "get-default-sink"])
            if not sink or sink in STALE_SINKS:
                sinks = [s["name"] for s in self._json("sinks") if s.get("name") not in STALE_SINKS]
                if not sinks:
                    raise AVError("no_sink", "No audio output device found")
                sink = sinks[0]
            self.real_sink = sink
            os.makedirs(DATA_DIR, exist_ok=True)
            with open(STATE_FILE, "w") as f:
                json.dump({"real_sink": sink}, f)

            self.null_mod = run(["pactl", "load-module", "module-null-sink",
                                 f"sink_name={CAPTURE_SINK}",
                                 "sink_properties=device.description=AlloraVoice"], check=True)
            self.loop_mod = run(["pactl", "load-module", "module-loopback",
                                 f"source={CAPTURE_SINK}.monitor", f"sink={sink}",
                                 "latency_msec=30", "source_dont_move=true", "sink_dont_move=true"],
                                check=True)
            run(["pactl", "set-default-sink", CAPTURE_SINK])
            time.sleep(0.3)
            self.move_streams()
            log("Routing aktiv:", sink)

    def _is_own(self, si):
        props = si.get("properties", {}) or {}
        if str(si.get("owner_module", "")) == str(self.loop_mod):
            return True
        if props.get("application.name") in (TTS_APP_NAME, "pw-play", "pw-cat"):
            return True
        try:
            if int(props.get("application.process.id", -1)) in self.own_pids:
                return True
        except (TypeError, ValueError):
            pass
        return False

    def move_streams(self):
        if not self.null_mod:
            return
        sinks = {s["index"]: s["name"] for s in self._json("sinks")}
        for si in self._json("sink-inputs"):
            if self._is_own(si):
                continue
            if sinks.get(si.get("sink")) == self.real_sink:
                run(["pactl", "move-sink-input", str(si["index"]), CAPTURE_SINK])

    def _loop_input(self):
        for si in self._json("sink-inputs"):
            if str(si.get("owner_module", "")) == str(self.loop_mod):
                return si["index"]
        return None

    def set_original_volume(self, pct, ramp=True):
        if not self.loop_mod:
            return
        idx = self._loop_input()
        if idx is None:
            return
        pct = max(0, min(150, int(pct)))
        steps = 4 if ramp else 1
        start = self.current_volume
        for i in range(1, steps + 1):
            v = int(start + (pct - start) * i / steps)
            run(["pactl", "set-sink-input-volume", str(idx), f"{v}%"])
            if ramp:
                time.sleep(0.04)
        self.current_volume = pct

    def stop(self):
        with self.lock:
            if not self.null_mod:
                return
            try:
                if self.real_sink:
                    run(["pactl", "set-default-sink", self.real_sink])
                    sinks = {s["index"]: s["name"] for s in self._json("sinks")}
                    for si in self._json("sink-inputs"):
                        if sinks.get(si.get("sink")) == CAPTURE_SINK and not self._is_own(si):
                            run(["pactl", "move-sink-input", str(si["index"]), self.real_sink])
                for mod in (self.loop_mod, self.null_mod):
                    if mod:
                        run(["pactl", "unload-module", str(mod)])
            finally:
                self.null_mod = self.loop_mod = None
                self.current_volume = 100
                try:
                    os.remove(STATE_FILE)
                except OSError:
                    pass
                log("Routing beendet")


# ─────────────────────── Medien-Player beobachten (MPRIS) ────────────────────
class MediaWatcher(threading.Thread):
    """Meldet Vor-/Zurückspulen und Pause aus Browsern & Playern (YouTube, Udemy, VLC …)."""
    MPRIS = "org.mpris.MediaPlayer2."
    PLAYER = "org.mpris.MediaPlayer2.Player"

    def __init__(self, on_event):
        super().__init__(daemon=True)
        self.on_event = on_event
        self.connected = False

    def run(self):
        try:
            import dbus_next  # noqa: F401
        except ImportError:
            log("dbus-next fehlt – Spul-Erkennung aus (Einrichtung erneut ausführen)")
            return
        while True:
            try:
                asyncio.run(self._main())
            except Exception as e:
                log("Medien-Beobachtung:", e)
            self.connected = False
            time.sleep(3)

    async def _call(self, bus, **kw):
        from dbus_next import Message
        return await asyncio.wait_for(bus.call(Message(**kw)), timeout=1.0)

    async def _main(self):
        from dbus_next.aio import MessageBus
        from dbus_next import MessageType
        bus = await MessageBus().connect()
        for rule in (f"type='signal',interface='{self.PLAYER}',member='Seeked'",
                     "type='signal',interface='org.freedesktop.DBus.Properties',"
                     "member='PropertiesChanged',path='/org/mpris/MediaPlayer2'"):
            await self._call(bus, destination="org.freedesktop.DBus", path="/org/freedesktop/DBus",
                             interface="org.freedesktop.DBus", member="AddMatch", signature="s", body=[rule])

        def handler(msg):
            if msg.message_type != MessageType.SIGNAL:
                return None
            if msg.member == "Seeked":
                self.on_event("seek")
            elif msg.member == "PropertiesChanged" and msg.body and msg.body[0] == self.PLAYER:
                st = msg.body[1].get("PlaybackStatus")
                if st is not None:
                    self.on_event("play" if st.value == "Playing" else "pause")
            return None

        bus.add_message_handler(handler)
        self.connected = True
        log("Medien-Beobachtung aktiv")

        # Zusätzlich: Position abfragen – erkennt Sprünge auch bei Playern ohne Seeked-Signal
        last = {}
        while bus.connected:
            await asyncio.sleep(0.5)
            try:
                names = (await self._call(bus, destination="org.freedesktop.DBus",
                                          path="/org/freedesktop/DBus", interface="org.freedesktop.DBus",
                                          member="ListNames")).body[0]
            except Exception:
                continue
            for n in [x for x in names if x.startswith(self.MPRIS)]:
                try:
                    reply = await self._call(bus, destination=n, path="/org/mpris/MediaPlayer2",
                                             interface="org.freedesktop.DBus.Properties", member="GetAll",
                                             signature="s", body=[self.PLAYER])
                except Exception:
                    continue
                if reply.message_type == MessageType.ERROR or not reply.body:
                    continue
                props = reply.body[0]
                status = props.get("PlaybackStatus")
                pos = props.get("Position")
                rate = props.get("Rate")
                now = time.monotonic()
                if status is None or status.value != "Playing" or pos is None:
                    last.pop(n, None)
                    continue
                p = pos.value / 1e6
                r = float(rate.value) if rate is not None else 1.0
                if n in last:
                    lp, lt = last[n]
                    expected = lp + (now - lt) * r
                    if p != lp and abs(p - expected) > 2.0:
                        self.on_event("seek")
                last[n] = (p, now)


# ─────────────────────────────── Spracherkennung ─────────────────────────────
class Recognizer:
    def __init__(self):
        self.key = None
        self.model = None

    def ensure(self, cfg, set_state):
        code = src_code(cfg)
        key = (cfg["recognizer"], code)
        if key == self.key:
            return
        self.model = None
        if cfg["recognizer"].startswith("whisper"):
            size = cfg["recognizer"].split("-", 1)[1]
            # reine Englisch-Modelle sind für Englisch schneller und genauer
            name = f"{size}.en" if code == "en" else size
            prev = set_state("loading_model") if set_state else None
            try:
                from faster_whisper import WhisperModel
            except ImportError:
                raise AVError("whisper_missing", "Whisper is not installed – choose 'Google Online' or run the setup again")
            log("Lade Whisper-Modell", name)
            # physische Kerne nutzen – Hyperthreading bremst Whisper eher
            threads = max(2, (os.cpu_count() or 4) // 2)
            self.model = WhisperModel(name, device="cpu", compute_type="int8", cpu_threads=threads)
            if set_state and prev:
                set_state(prev)
        self.key = key

    def transcribe(self, audio_i16, cfg):
        """Liefert (Text, erkannte Sprache)."""
        code = src_code(cfg)
        if cfg["recognizer"].startswith("whisper"):
            audio = audio_i16.astype(np.float32) / 32768.0
            whisper_lang = None if code == "auto" else (cfg["source"].get("whisper") or code)
            segs, info = self.model.transcribe(
                audio, language=whisper_lang,
                beam_size=1, best_of=1, temperature=0.0, vad_filter=False,
                condition_on_previous_text=False, without_timestamps=True)
            parts = [s.text.strip() for s in segs if s.no_speech_prob < 0.6]
            return " ".join(p for p in parts if p).strip(), (info.language if info else code)
        import speech_recognition as sr
        data = sr.AudioData(audio_i16.tobytes(), SR, 2)
        lang = "en-US" if code == "auto" else cfg["source"].get("stt", "en-US")
        try:
            return sr.Recognizer().recognize_google(data, language=lang), code
        except sr.UnknownValueError:
            return "", code


# ─────────────────────────────── Übersetzung ─────────────────────────────────
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"


def _get_json(url, timeout=5):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def _tr_deepl(text, src, tgt, cfg):
    key = (cfg.get("deeplKey") or "").strip()
    if not key:
        raise RuntimeError("no DeepL key")
    host = "api-free.deepl.com" if key.endswith(":fx") else "api.deepl.com"
    body = {"text": text, "target_lang": tgt["deepl"]}
    if src:
        body["source_lang"] = src["deeplSource"]
    req = urllib.request.Request(f"https://{host}/v2/translate",
                                 data=urllib.parse.urlencode(body).encode(),
                                 headers={"Authorization": f"DeepL-Auth-Key {key}", "User-Agent": UA})
    with urllib.request.urlopen(req, timeout=6) as r:
        return json.loads(r.read())["translations"][0]["text"]


def _g(lang, default="auto"):
    return lang.get("google", lang["code"]) if lang else default


def _tr_google_gtx(text, src, tgt, cfg):
    # gleiche Schnittstelle, die auch die Chrome-Übersetzungsfunktion nutzt
    q = urllib.parse.urlencode({"client": "gtx", "sl": _g(src), "tl": _g(tgt), "dt": "t", "q": text})
    data = _get_json(f"https://translate.googleapis.com/translate_a/single?{q}")
    return "".join(part[0] for part in data[0] if part and part[0])


def _tr_google_dict(text, src, tgt, cfg):
    q = urllib.parse.urlencode({"client": "dict-chrome-ex", "sl": _g(src), "tl": _g(tgt), "q": text})
    data = _get_json(f"https://clients5.google.com/translate_a/t?{q}")
    first = data[0]
    return first[0] if isinstance(first, list) else first


def _tr_mymemory(text, src, tgt, cfg):
    pair = f"{_g(src, 'autodetect')}|{_g(tgt)}"
    q = urllib.parse.urlencode({"q": text[:500], "langpair": pair})
    data = _get_json(f"https://api.mymemory.translated.net/get?{q}")
    if int(data.get("responseStatus", 200)) != 200:
        raise RuntimeError(data.get("responseDetails", "MyMemory error"))
    return data["responseData"]["translatedText"]


def _tr_deep_translator(text, src, tgt, cfg):
    from deep_translator import GoogleTranslator
    return GoogleTranslator(source=_g(src), target=_g(tgt)).translate(text) or ""


PROVIDERS = {
    "deepl": _tr_deepl,
    "google": _tr_google_gtx,
    "google2": _tr_google_dict,
    "google3": _tr_deep_translator,
    "mymemory": _tr_mymemory,
}
_cooldown = {}           # Anbieter -> Zeitpunkt, ab dem er wieder probiert wird
_cache = {}              # gleiche Sätze nicht doppelt anfragen
_last_call = [0.0]
_tr_lock = threading.Lock()


def translate(text, cfg):
    src = None if src_code(cfg) == "auto" else cfg["source"]
    tgt = cfg.get("target") or LANG_DE
    ckey = (text, src["code"] if src else "auto", tgt["code"])
    if ckey in _cache:
        return _cache[ckey]
    order = ["google", "google2", "mymemory", "google3"]
    if (cfg["translator"] == "deepl" and cfg.get("deeplKey") and tgt.get("deepl")
            and (src is None or src.get("deeplSource"))):
        order.insert(0, "deepl")
    errors = []
    with _tr_lock:
        # höchstens ~4 Anfragen pro Sekunde
        wait = 0.25 - (time.time() - _last_call[0])
        if wait > 0:
            time.sleep(wait)
        for name in order:
            if _cooldown.get(name, 0) > time.time():
                continue
            try:
                _last_call[0] = time.time()
                out = (PROVIDERS[name](text, src, tgt, cfg) or "").strip()
                if out:
                    if len(_cache) > 500:
                        _cache.clear()
                    _cache[ckey] = out
                    return out
            except Exception as e:
                msg = str(e)
                # Sperre: Anbieter für 2 Minuten überspringen, sonst 20 Sekunden
                blocked = "429" in msg or "too many" in msg.lower() or "403" in msg
                _cooldown[name] = time.time() + (120 if blocked else 20)
                errors.append(f"{name}: {msg[:80]}")
                log("Übersetzer", name, "fehlgeschlagen:", msg[:120])
    raise AVError("translate_all", "All translators unreachable – check your internet connection. "
                  + "; ".join(errors[:2]))


# ─────────────────────────── Stimmenliste (Microsoft) ─────────────────────────
VOICES_FILE = os.path.join(DATA_DIR, "voices.json")
_voices_lock = threading.Lock()


def get_voices(max_age_days=7):
    """Alle Microsoft-Neural-Stimmen als [{n: ShortName, g: Gender, l: Locale}] –
    wird eine Woche lang zwischengespeichert."""
    with _voices_lock:
        cached = []
        try:
            with open(VOICES_FILE) as f:
                cached = json.load(f)
            if time.time() - os.path.getmtime(VOICES_FILE) < max_age_days * 86400 and cached:
                return cached
        except Exception:
            pass
        try:
            import edge_tts
            raw = asyncio.run(edge_tts.list_voices())
            voices = [{"n": v["ShortName"], "g": v.get("Gender", ""), "l": v.get("Locale", "")}
                      for v in raw if v.get("ShortName") and v.get("Locale")]
            voices.sort(key=lambda v: v["n"])
            if voices:
                os.makedirs(DATA_DIR, exist_ok=True)
                with open(VOICES_FILE, "w") as f:
                    json.dump(voices, f)
                log(f"{len(voices)} Stimmen geladen")
                return voices
        except Exception as e:
            log("Stimmenliste:", e)
        return cached


def fallback_voice(cfg):
    """Ersatzstimme gleicher Sprache, falls die gewählte Stimme nicht antwortet."""
    tgt = cfg.get("target") or LANG_DE
    gender = cfg.get("gender", "female")
    fb = (tgt.get("fallback") or {}).get(gender)
    if fb and fb != cfg.get("voice"):
        return fb
    g = "Male" if gender == "male" else "Female"
    loc = (tgt.get("stt") or tgt.get("code", "de")).split("-")[0] + "-"
    try:
        with open(VOICES_FILE) as f:
            for v in json.load(f):
                if v["l"].startswith(loc) and v["g"] == g and v["n"] != cfg.get("voice"):
                    return v["n"]
    except Exception:
        pass
    return None


# ─────────────────────────── Sprachausgabe (gestreamt) ───────────────────────
DEFAULT_CPS = 15.0   # Zeichen pro Sekunde einer Neural-Stimme bei Tempo 0 (wird nachgemessen)


class Speech:
    """Lädt die Neural-Stimme im Hintergrund und dekodiert sie stückweise.
    Die Wiedergabe kann schon beim ersten Audiostück beginnen."""

    def __init__(self, text, voice, rate, pitch, fallback=None, ep=0, t_end=0.0, dur=0.0):
        self.text, self.voice, self.rate, self.pitch = text, voice, int(rate), int(pitch)
        self.fallback = fallback
        self.ep, self.t_end, self.dur = ep, t_end, dur
        self.created = time.time()
        self.ready_at = None      # wann das erste Audiostück da war
        self.chunks = deque()
        self.total = 0
        self.done = False
        self.cancelled = False
        self.error = None
        self.cv = threading.Condition()
        threading.Thread(target=self._run, daemon=True).start()

    @property
    def seconds(self):
        return self.total / 2 / TTS_SR

    def est_seconds(self, cps0):
        """Geschätzte Länge der fertigen Ansage (Sekunden, ohne Wiedergabe-Tempo)."""
        if self.done:
            return self.seconds
        return max(self.seconds, len(self.text) / (cps0 * (1 + self.rate / 100)))

    def cancel(self):
        self.cancelled = True
        with self.cv:
            self.cv.notify_all()

    def _push(self, pcm):
        with self.cv:
            if self.ready_at is None:
                self.ready_at = time.time()
            self.chunks.append(pcm)
            self.total += len(pcm)
            self.cv.notify_all()

    def _run(self):
        try:
            try:
                asyncio.run(self._stream(self.voice))
            except Exception as e:
                if self.total == 0 and self.fallback and self.fallback != self.voice and not self.cancelled:
                    log("Stimme fehlgeschlagen:", self.voice, e, "→", self.fallback)
                    asyncio.run(self._stream(self.fallback))
                else:
                    raise
        except Exception as e:
            self.error = e
            log("TTS:", e)
        finally:
            with self.cv:
                self.done = True
                self.cv.notify_all()

    async def _stream(self, voice):
        import av
        import edge_tts
        ctx = av.CodecContext.create("mp3", "r")
        res = av.AudioResampler(format="s16", layout="mono", rate=TTS_SR)

        def decode(data):
            for pkt in ctx.parse(data):
                try:
                    frames = ctx.decode(pkt)
                except av.error.InvalidDataError:
                    continue   # Kopf-/Infoblock oder kaputtes Stück überspringen
                for fr in frames:
                    for f in res.resample(fr):
                        self._push(f.to_ndarray().tobytes())

        com = edge_tts.Communicate(self.text, voice, rate=f"{self.rate:+d}%", pitch=f"{self.pitch:+d}Hz")
        async for chunk in com.stream():
            if self.cancelled:
                return
            if chunk["type"] == "audio" and chunk["data"]:
                decode(chunk["data"])
        try:
            decode(None)  # Parser leeren
            for fr in ctx.decode(None):
                for f in res.resample(fr):
                    self._push(f.to_ndarray().tobytes())
            for f in res.resample(None):
                self._push(f.to_ndarray().tobytes())
        except Exception:
            pass

    def read(self, timeout=0.1):
        """Nächstes PCM-Stück, b'' wenn gerade nichts da ist, None wenn fertig."""
        with self.cv:
            if not self.chunks and not self.done and not self.cancelled:
                self.cv.wait(timeout)
            if self.chunks:
                return self.chunks.popleft()
            if self.done or self.cancelled:
                return None
            return b""


class Stretcher:
    """Ändert das Wiedergabe-Tempo stufenlos, ohne die Tonhöhe zu verändern (ffmpeg atempo)."""

    def __init__(self):
        self.tempo = 1.0
        self.graph = None
        self.pts = 0
        self.ok = True

    def _build(self, tempo):
        import av
        from fractions import Fraction
        g = av.filter.Graph()
        src = g.add_abuffer(format="s16", sample_rate=TTS_SR, layout="mono", time_base=Fraction(1, TTS_SR))
        at = g.add("atempo", f"{tempo:.3f}")
        sink = g.add("abuffersink")
        src.link_to(at)
        at.link_to(sink)
        g.configure()
        self.pts = 0
        return g

    @staticmethod
    def _pull(g):
        out = bytearray()
        while True:
            try:
                f = g.pull()
            except Exception:      # BlockingIOError (braucht mehr Daten) oder EOFError
                break
            a = f.to_ndarray()
            if a.dtype != np.int16:
                a = np.clip(a * 32767, -32768, 32767).astype(np.int16)
            out += a.reshape(-1).tobytes()
        return bytes(out)

    def flush(self):
        if self.graph is None:
            return b""
        try:
            self.graph.push(None)
            out = self._pull(self.graph)
        except Exception:
            out = b""
        self.graph = None
        return out

    def process(self, pcm, tempo):
        if not self.ok:
            return pcm
        out = b""
        if abs(tempo - self.tempo) >= 0.03 or (self.graph is None and tempo > 1.02):
            out += self.flush()
            self.tempo = tempo
            if tempo <= 1.02:
                self.tempo = 1.0
            else:
                try:
                    self.graph = self._build(tempo)
                except Exception as e:
                    log("Tempo-Filter nicht verfügbar:", e)
                    self.ok, self.graph, self.tempo = False, None, 1.0
        if self.graph is None:
            return out + pcm
        try:
            import av
            from fractions import Fraction
            a = np.frombuffer(pcm, dtype=np.int16).reshape(1, -1)
            fr = av.AudioFrame.from_ndarray(a, format="s16", layout="mono")
            fr.sample_rate = TTS_SR
            fr.pts = self.pts
            fr.time_base = Fraction(1, TTS_SR)
            self.pts += a.shape[1]
            self.graph.push(fr)
            return out + self._pull(self.graph)
        except Exception as e:
            log("Tempo-Filter:", e)
            self.ok, self.graph, self.tempo = False, None, 1.0
            return out + pcm


def _merge_waiting(q, first, ep, max_items=None):
    """Holt alle wartenden Einträge derselben Epoche dazu (nichts geht verloren)."""
    items = [first]
    while max_items is None or len(items) < max_items:
        try:
            nxt = q.get_nowait()
        except queue.Empty:
            break
        if nxt[0] == ep:
            items.append(nxt)
    return items


# ─────────────────────────────── Engine ──────────────────────────────────────
MAX_TEMPO = 1.35       # schnellste Wiedergabe ohne Tonhöhen-Änderung
MAX_RATE_BOOST = 80    # zusätzliches Sprechtempo der Stimme in %
MAX_MERGE_AUDIO = 14.0 # Sekunden Originalton, die höchstens zusammengefasst werden


class Engine:
    def __init__(self):
        self.cfg = dict(DEFAULT_CFG)
        self.lock = threading.Lock()
        self.router = Router()
        self.recognizer = Recognizer()
        self.running = False
        self.state = "idle"
        self.error = ""
        self.error_code = ""
        self.error_arg = ""
        self.level = 0.0
        self.src_text = ""
        self.dst_text = ""
        self.history = deque(maxlen=60)
        self.seg_q = queue.Queue()
        self.tts_q = queue.Queue()
        self.play_q = queue.Queue()
        self.speaking = False
        self.stop_evt = threading.Event()
        self.capture_proc = None
        self.play_proc = None
        self.threads = []
        self.last_speech_end = 0.0
        self.gen = 0          # Lebensdauer der Arbeits-Threads (Start/Stopp)
        self.epoch = 0        # erhöht sich bei Spulen/Pause → alles Ältere wird verworfen
        self.lag = 0.0        # gesamter Versatz zum Original (Sekunden)
        self.backlog_s = 0.0  # davon: Rückstand durch Warten (ohne Verarbeitungszeit)
        self.tempo = 1.0      # aktuelles Wiedergabe-Tempo
        self.skipped = 0      # übersprungene Sätze (nur im Notfall)
        self.cps = {}         # gemessene Zeichen pro Sekunde je Stimme (bei Tempo 0)
        self.cur_end = 0.0    # geschätztes Ende der laufenden Ansage
        self.media_event = ("", 0.0)
        self.last_flush = 0.0
        self.paused = False
        self.media = MediaWatcher(self.on_media_event)
        self.media.start()

    # ── Status ──
    def set_error(self, code="", arg="", text=""):
        self.error_code, self.error_arg, self.error = code, arg, text

    def set_state(self, s):
        prev = self.state
        self.state = s
        return prev

    def status(self):
        kind, t = self.media_event
        return {
            "ok": True, "version": VERSION, "running": self.running, "state": self.state,
            "error": self.error, "errorCode": self.error_code, "errorArg": self.error_arg,
            "level": round(self.level, 3),
            "srcText": self.src_text, "dstText": self.dst_text,
            "lag": round(self.lag, 1), "backlog": round(self.backlog_s, 1),
            "tempo": round(self.tempo, 2), "skipped": self.skipped,
            "mediaEvent": kind if time.time() - t < 3 else "",
            "mediaConnected": self.media.connected,
            "queue": self.seg_q.qsize() + self.tts_q.qsize() + self.play_q.qsize(),
            "history": list(self.history)[-40:],
        }

    def update_cfg(self, new):
        with self.lock:
            for k, v in (new or {}).items():
                if k in DEFAULT_CFG:
                    self.cfg[k] = v
        if self.running:
            threading.Thread(target=self._apply_volume, daemon=True).start()

    def _apply_volume(self):
        c = self.cfg
        target = c["originalVolume"]
        if self.speaking and c["duck"]:
            target = c["originalVolume"] * c["duckLevel"] / 100
        try:
            self.router.set_original_volume(target)
        except Exception as e:
            log("Lautstärke:", e)

    def cps0(self, voice=None):
        return self.cps.get(voice or self.cfg["voice"], DEFAULT_CPS)

    def pending_speech(self, include_current=True):
        """Wie viele Sekunden Ansage noch vor einem neuen Satz liegen."""
        cps0 = self.cps0()
        total = 0.0
        if include_current:
            total += max(0.0, self.cur_end - time.time())
        for sp in list(self.play_q.queue):
            if isinstance(sp, Speech):
                total += sp.est_seconds(self.cps.get(sp.voice, cps0)) / max(1.0, self.tempo)
        for item in list(self.tts_q.queue):
            total += len(item[1]) / cps0
        return total

    # ── Spulen / Pause ──
    def on_media_event(self, kind):
        if kind == "play":
            self.paused = False
            return
        if not self.running or not self.cfg.get("mediaSync", True):
            return
        now = time.time()
        if kind == "seek" and now - self.last_flush < 0.8:
            return
        if kind == "pause":
            if self.paused:
                return
            self.paused = True
        log("Medien:", kind, "→ alles Alte verworfen")
        self.flush()
        self.media_event = (kind, now)

    def flush(self):
        """Verwirft alle wartenden und laufenden Übersetzungen sofort."""
        self.epoch += 1
        self.last_flush = time.time()
        for q in (self.seg_q, self.tts_q, self.play_q):
            while True:
                try:
                    item = q.get_nowait()
                except queue.Empty:
                    break
                if isinstance(item, Speech):
                    item.cancel()
        p = self.play_proc
        if p and p.poll() is None:
            p.kill()
        self.lag = self.backlog_s = 0.0
        self.cur_end = 0.0
        self.tempo = 1.0

    # ── Start / Stopp ──
    def start(self):
        if self.running:
            return
        self.set_error()
        self.stop_evt.clear()
        self.gen += 1
        self.epoch += 1
        self.running = True
        self.paused = False
        self.lag = self.backlog_s = 0.0
        self.tempo = 1.0
        self.skipped = 0
        self.set_state("starting")
        threading.Thread(target=self._start_worker, daemon=True).start()

    def _start_worker(self):
        try:
            self.recognizer.ensure(self.cfg, self.set_state)
            if self.stop_evt.is_set():
                return
            self.router.start()
            self.router.set_original_volume(self.cfg["originalVolume"], ramp=False)
            gen = self.gen
            self.threads = [
                threading.Thread(target=self._capture_loop, args=(gen,), daemon=True),
                threading.Thread(target=self._recognize_loop, args=(gen,), daemon=True),
                threading.Thread(target=self._synth_loop, args=(gen,), daemon=True),
                threading.Thread(target=self._play_loop, args=(gen,), daemon=True),
                threading.Thread(target=self._housekeeping, args=(gen,), daemon=True),
            ]
            for t in self.threads:
                t.start()
            self.set_state("listening")
        except Exception as e:
            log("Startfehler:", e)
            if isinstance(e, AVError):
                self.set_error(e.code, e.arg, str(e))
            else:
                self.set_error("start", str(e), str(e))
            self.running = False
            self.set_state("error")
            try:
                self.router.stop()
            except Exception:
                pass

    def stop(self):
        self.stop_evt.set()
        self.gen += 1
        self.running = False
        self.flush()
        p = self.capture_proc
        if p and p.poll() is None:
            p.kill()
        self.speaking = False
        try:
            self.router.stop()
        except Exception as e:
            log("Stoppfehler:", e)
        self.level = 0
        self.set_state("idle")

    # ── 1. Abgreifen + Satz-Segmentierung ──
    def _capture_loop(self, gen):
        cmd = ["parec", f"--device={CAPTURE_SINK}.monitor", "--rate=16000", "--channels=1",
               "--format=s16le", "--raw", "--latency-msec=30", "--client-name=AlloraVoiceCapture"]
        self.capture_proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        stream = self.capture_proc.stdout
        frames, in_speech, silence, voiced = [], False, 0.0, 0.0
        preroll = deque(maxlen=7)  # ~210 ms Vorlauf
        noise = 0.004
        fdur = FRAME / SR
        ep = self.epoch
        while not self.stop_evt.is_set() and gen == self.gen:
            raw = stream.read(FRAME * 2)
            if not raw or len(raw) < FRAME * 2:
                if self.capture_proc.poll() is not None:
                    self.set_error("capture_ended", "", "Audio capture stopped")
                    break
                continue
            if ep != self.epoch:
                # gespult: angefangenen Satz von der alten Stelle wegwerfen
                ep = self.epoch
                frames, in_speech, silence, voiced = [], False, 0.0, 0.0
                preroll.clear()
            x = np.frombuffer(raw, dtype=np.int16)
            rms = float(np.sqrt(np.mean((x.astype(np.float32) / 32768.0) ** 2)))
            self.level = min(1.0, self.level * 0.6 + rms * 6 * 0.4)
            sens = max(1, min(10, int(self.cfg.get("minLevel", 3))))
            thr = max(0.003 * sens / 3, noise * 2.5)
            if not in_speech:
                noise = noise * 0.995 + rms * 0.005 if rms < thr else noise
            is_voice = rms > thr
            sil_end, max_len = RESPONSIVENESS.get(self.cfg["responsiveness"], RESPONSIVENESS["balanced"])

            if not in_speech:
                preroll.append(x)
                if is_voice:
                    in_speech, frames, silence, voiced = True, list(preroll), 0.0, 0.0
                continue

            frames.append(x)
            if is_voice:
                silence = 0.0
                voiced += fdur
            else:
                silence += fdur
            length = len(frames) * fdur

            if silence >= sil_end or length >= max_len:
                if length >= max_len and silence < sil_end:
                    # an der leisesten Stelle der letzten Sekunde schneiden
                    tail = frames[-33:]
                    energies = [float(np.mean(np.abs(f.astype(np.float32)))) for f in tail]
                    cut = len(frames) - len(tail) + int(np.argmin(energies)) + 1
                    seg, rest = frames[:cut], frames[cut:]
                else:
                    seg, rest = frames, []
                if voiced >= 0.35:
                    # Zeitpunkt, an dem dieser Satz im Original zu Ende gesprochen war
                    t_end = time.time() - len(rest) * fdur - (silence if not rest else 0.0)
                    self.seg_q.put((ep, np.concatenate(seg), t_end))
                if rest:
                    frames, silence, voiced = rest, 0.0, len(rest) * fdur
                else:
                    in_speech, frames = False, []
                    preroll.clear()

    # ── 2. Erkennen + Übersetzen ──
    def _recognize_loop(self, gen):
        last_out = ""
        while not self.stop_evt.is_set() and gen == self.gen:
            try:
                first = self.seg_q.get(timeout=0.2)
            except queue.Empty:
                continue
            ep = first[0]
            if ep != self.epoch:
                continue
            # Wartende Stücke zusammenfassen statt wegwerfen – Whisper ist mit einem
            # längeren Stück schneller als mit mehreren kurzen, und es geht nichts verloren.
            items = _merge_waiting(self.seg_q, first, ep)
            total = sum(len(a) for _, a, _ in items) / SR
            while len(items) > 1 and total > MAX_MERGE_AUDIO:
                if not self.cfg["syncMode"]:
                    break
                dropped = items.pop(0)          # nur im Extremfall: Ältestes weglassen
                total -= len(dropped[1]) / SR
                self.skipped += 1
            audio = np.concatenate([a for _, a, _ in items])
            t_end = items[-1][2]
            dur = len(audio) / SR
            try:
                self.recognizer.ensure(self.cfg, self.set_state)
                if self.state == "listening":
                    self.set_state("recognizing")
                text, detected = self.recognizer.transcribe(audio, self.cfg)
                text = text.strip()
                if ep != self.epoch or not text or text.lower() in JUNK or len(text) < 2:
                    continue
                tgt = self.cfg.get("target") or LANG_DE
                if src_code(self.cfg) == "auto" and detected == tgt["code"]:
                    continue  # ist schon in der Zielsprache
                out = translate(text, self.cfg).strip()
                if ep != self.epoch or not out or out == last_out:
                    continue
                last_out = out
                self.src_text, self.dst_text = text, out
                self.history.append({"t": time.strftime("%H:%M:%S"), "src": text, "dst": out})
                self.tts_q.put((ep, out, t_end, dur))
                self.set_error()
            except AVError as e:
                log("Erkennung/Übersetzung:", e)
                self.set_error(e.code, e.arg, str(e))
            except Exception as e:
                log("Erkennung/Übersetzung:", e)
                self.set_error("translate", str(e), f"Translation: {e}")
            finally:
                if self.running and not self.speaking and self.state in ("recognizing", "loading_model"):
                    self.set_state("listening")

    # ── 3. Sprachsynthese mit vorausschauender Tempo-Planung ──
    def _plan_rate(self, text, voice, dur):
        """Sprechtempo so wählen, dass die Ansage in die Zeit des Originals passt
        und vorhandener Rückstand nach und nach abgebaut wird."""
        c = self.cfg
        base = int(c["rate"])
        if not c["adaptiveTempo"]:
            return max(-50, min(100, base))
        cps0 = self.cps0(voice)
        est = len(text) / (cps0 * (1 + base / 100))      # Dauer bei Grundtempo
        ahead = self.pending_speech()                     # was noch vorher gesprochen wird
        budget = dur - 0.6 * ahead                        # 60 % des Rückstands jetzt aufholen
        budget = max(budget, dur * 0.45, 0.6)
        factor = est / budget
        rate = base
        if factor > 1.0:
            rate = base + min(MAX_RATE_BOOST, int(round((factor - 1) * 100 * (1 + base / 100))))
        return max(-50, min(100, rate))

    def _synth_loop(self, gen):
        while not self.stop_evt.is_set() and gen == self.gen:
            try:
                first = self.tts_q.get(timeout=0.2)
            except queue.Empty:
                continue
            ep = first[0]
            if ep != self.epoch:
                continue
            # mehrere fertige Übersetzungen → zu einer Ansage zusammenfassen (nichts fällt weg)
            items = _merge_waiting(self.tts_q, first, ep)
            text = " ".join(t for _, t, _, _ in items)
            t_end = items[-1][2]
            dur = sum(d for _, _, _, d in items)
            c = self.cfg
            voice = c["voice"]
            rate = self._plan_rate(text, voice, dur)
            fallback = fallback_voice(c)
            # Speech lädt sofort im Hintergrund – auch während der vorige Satz noch läuft
            self.play_q.put(Speech(text, voice, rate, c["pitch"], fallback, ep, t_end, dur))

    # ── 4. Wiedergabe mit stufenlosem Tempo ──
    def _pacat(self, target):
        vol = max(0.0, min(1.0, self.cfg["ttsVolume"] / 100))   # über 100 % → Verstärkung in _play
        cmd = ["pacat", "--playback", "--raw", "--format=s16le", f"--rate={TTS_SR}", "--channels=1",
               "--latency-msec=60", f"--client-name={TTS_APP_NAME}",
               f"--property=application.name={TTS_APP_NAME}", f"--volume={int(65536 * vol)}"]
        if target:
            cmd.append(f"--device={target}")
        p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.router.own_pids.add(p.pid)
        return p

    def _desired_tempo(self):
        """Je mehr Ansagen warten, desto schneller – sanft, ohne Sprünge."""
        if not self.cfg["adaptiveTempo"]:
            return 1.0
        waiting = self.pending_speech(include_current=False)
        t = 1.0 + 0.07 * waiting
        return max(1.0, min(MAX_TEMPO, round(t / 0.05) * 0.05))

    def _play(self, sp, target=None, adaptive=True):
        """Spielt eine Speech gestreamt ab. False, wenn durch Spulen/Stopp abgebrochen."""
        p = self._pacat(target)
        self.play_proc = p
        stretch = Stretcher()
        written = 0.0
        t0 = time.time()
        ok = True

        def write(data):
            gain = min(1.5, self.cfg["ttsVolume"] / 100)
            if gain > 1.0:
                x = np.frombuffer(data, dtype=np.int16).astype(np.float32) * gain
                data = np.clip(x, -32768, 32767).astype(np.int16).tobytes()
            p.stdin.write(data)
            p.stdin.flush()
            return len(data) / 2 / TTS_SR

        try:
            while True:
                if self.stop_evt.is_set() or sp.cancelled or sp.ep != self.epoch:
                    ok = False
                    break
                data = sp.read(0.1)
                if data is None:
                    break
                if not data:
                    continue
                tempo = self._desired_tempo() if adaptive else 1.0
                data = stretch.process(data, tempo)
                self.tempo = stretch.tempo
                if data:
                    try:
                        written += write(data)
                    except (BrokenPipeError, ValueError, OSError):
                        ok = False
                        break
                # geschätztes Ende dieser Ansage (für die Tempo-Planung der nächsten)
                rest = max(0.0, sp.est_seconds(self.cps0(sp.voice)) - sp.seconds) / max(1.0, stretch.tempo)
                self.cur_end = max(t0 + written, time.time()) + rest
            if ok:
                try:
                    tail = stretch.flush()
                    if tail:
                        written += write(tail)
                    p.stdin.close()
                except (BrokenPipeError, ValueError, OSError):
                    pass
                self.cur_end = t0 + written
                while p.poll() is None:   # Rest ausspielen lassen
                    if self.stop_evt.is_set() or sp.ep != self.epoch:
                        ok = False
                        break
                    time.sleep(0.03)
        finally:
            if p.poll() is None:
                p.kill()
            try:
                p.wait(timeout=1)
            except Exception:
                pass
            self.router.own_pids.discard(p.pid)
            self.cur_end = time.time() if not ok else self.cur_end
        return ok

    def _play_loop(self, gen):
        while not self.stop_evt.is_set() and gen == self.gen:
            try:
                sp = self.play_q.get(timeout=0.2)
            except queue.Empty:
                if self.speaking and time.time() - self.last_speech_end > 0.4:
                    self.speaking = False
                    self.tempo = 1.0
                    self._apply_volume()
                    if self.running:
                        self.set_state("listening")
                continue
            if sp.ep != self.epoch:
                sp.cancel()
                continue

            # Rückstand = reine Wartezeit (ohne die normale Verarbeitungszeit fürs Erkennen,
            # Übersetzen und Laden). Nur dieser Teil zählt für den Notfall-Sprung.
            ready = sp.ready_at or time.time()
            self.backlog_s = max(0.0, time.time() - ready)
            if (self.cfg["syncMode"] and self.backlog_s > float(self.cfg["maxLag"])
                    and not self.play_q.empty()):
                # Notfall: nur zwischen zwei Ansagen springen, nie mitten im Satz
                sp.cancel()
                self.skipped += 1
                log(f"Notfall-Sprung: {self.backlog_s:.1f} s Rückstand")
                continue

            lag = max(0.0, time.time() - sp.t_end)
            self.lag = lag if self.lag == 0 else self.lag * 0.5 + lag * 0.5
            if not self.speaking:
                self.speaking = True
                self._apply_volume()
            self.set_state("speaking")

            if not self._play(sp, self.router.real_sink):
                sp.cancel()
            elif sp.seconds > 0.3:
                # Sprechgeschwindigkeit der Stimme nachmessen (für die Tempo-Planung)
                measured = len(sp.text) / sp.seconds / (1 + sp.rate / 100)
                old = self.cps.get(sp.voice)
                self.cps[sp.voice] = measured if old is None else old * 0.6 + measured * 0.4
            if sp.error and not sp.total:
                self.set_error("tts", str(sp.error), f"Voice: {sp.error}")
            self.last_speech_end = time.time()

    def _housekeeping(self, gen):
        while not self.stop_evt.wait(2.0) and gen == self.gen:
            try:
                self.router.move_streams()
            except Exception as e:
                log("Streams:", e)
            if not self.speaking and self.seg_q.empty() and self.tts_q.empty():
                self.lag *= 0.7          # Anzeige beruhigt sich in Sprechpausen
                self.backlog_s *= 0.5

    def test_voice(self, sample):
        def worker():
            c = self.cfg
            text = sample
            tgt = c.get("target") or LANG_DE
            if not text:
                text = "Hello! This is how I sound when I translate for you."
                if tgt.get("code") != "en":
                    try:
                        text = translate(text, dict(c, source=LANG_EN))
                    except Exception as e:
                        log("Testsatz:", e)
            sp = Speech(text, c["voice"], c["rate"], c["pitch"], fallback_voice(c), ep=self.epoch)
            self._play(sp, self.router.real_sink if self.running else None, adaptive=False)
            if sp.error and not sp.total:
                self.set_error("tts", str(sp.error), f"Voice: {sp.error}")
        threading.Thread(target=worker, daemon=True).start()


ENGINE = None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if not n:
            return {}
        try:
            return json.loads(self.rfile.read(n) or b"{}")
        except json.JSONDecodeError:
            return {}

    def do_OPTIONS(self):
        self._send({"ok": True})

    def do_GET(self):
        if self.path == "/ping":
            self._send({"ok": True, "version": VERSION})
        elif self.path == "/status":
            self._send(ENGINE.status())
        elif self.path == "/config":
            self._send(ENGINE.cfg)
        elif self.path == "/voices":
            self._send({"ok": True, "voices": get_voices()})
        else:
            self._send({"ok": False}, 404)

    def do_POST(self):
        body = self._body()
        if self.path == "/config":
            ENGINE.update_cfg(body)
        elif self.path == "/start":
            ENGINE.update_cfg(body)
            ENGINE.start()
        elif self.path == "/stop":
            ENGINE.stop()
        elif self.path == "/test":
            sample = body.pop("sample", None) or ""
            ENGINE.update_cfg(body)
            ENGINE.test_voice(sample)
        elif self.path == "/clear":
            ENGINE.history.clear()
            ENGINE.src_text = ENGINE.dst_text = ""
            ENGINE.skipped = 0
        elif self.path == "/quit":
            self._send({"ok": True})
            threading.Thread(target=shutdown, daemon=True).start()
            return
        else:
            self._send({"ok": False}, 404)
            return
        self._send(ENGINE.status())


SERVER = None


def shutdown(*_):
    try:
        if ENGINE:
            ENGINE.stop()
    finally:
        if SERVER:
            threading.Thread(target=SERVER.shutdown, daemon=True).start()


def stop_old_versions():
    for port in OLD_PORTS:
        try:
            req = urllib.request.Request(f"http://127.0.0.1:{port}/quit", data=b"{}", method="POST")
            urllib.request.urlopen(req, timeout=1)
            log("Alte Version auf Port", port, "beendet")
        except Exception:
            pass


def main():
    global SERVER, ENGINE
    os.makedirs(DATA_DIR, exist_ok=True)
    try:
        SERVER = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    except OSError:
        log("Backend läuft bereits.")
        return
    ENGINE = Engine()
    stop_old_versions()
    try:
        Router().cleanup_stale()
    except Exception as e:
        log("Cleanup:", e)
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    log(f"AlloraVoice-Backend {VERSION} auf Port {PORT}")
    try:
        SERVER.serve_forever()
    finally:
        ENGINE.stop()


if __name__ == "__main__":
    main()
