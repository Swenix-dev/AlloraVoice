/*
 * SPDX-FileCopyrightText: 2026 SeaQ
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
/*
 * AlloraVoice – Live-Übersetzung · Plasma 6 Widget
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "languages.js" as Languages

PlasmoidItem {
    id: root

    readonly property string apiBase: "http://127.0.0.1:47820"
    readonly property string backendVersion: "2.5.0"
    readonly property string backendDir: decodeURIComponent(Qt.resolvedUrl("../backend/").toString().replace("file://", ""))
    readonly property var cfg: Plasmoid.configuration

    // ── Zustand vom Backend ──
    property bool backendOnline: false
    property bool installed: true
    property bool running: false
    property bool starting: false
    property string stateName: "offline"
    property real level: 0
    property string srcText: ""
    property string dstText: ""
    property var history: []
    property string errorText: ""
    property int queueSize: 0
    property real lag: 0
    property int skipped: 0
    property string mediaEvent: ""
    property real backlog: 0
    property real tempo: 1
    property bool mediaConnected: false

    // ── Farben des KDE-Farbschemas (kdeglobals) – nicht die des Plasma-Stils ──
    SystemPalette { id: palFallback; colorGroup: SystemPalette.Active }
    property var scheme: ({})
    function schemeColor(key, fallback) {
        var v = scheme[key]
        if (!v) return fallback
        var p = v.split(",")
        if (p.length < 3) return fallback
        return Qt.rgba(p[0] / 255, p[1] / 255, p[2] / 255, p.length > 3 ? p[3] / 255 : 1)
    }
    readonly property color cWindow:     schemeColor("win", palFallback.window)
    readonly property color cWindowAlt:  schemeColor("winAlt", palFallback.alternateBase)
    readonly property color cText:       schemeColor("winText", palFallback.windowText)
    readonly property color cDisabled:   schemeColor("winInactive", Qt.rgba(cText.r, cText.g, cText.b, 0.6))
    readonly property color cView:       schemeColor("view", palFallback.base)
    readonly property color cViewText:   schemeColor("viewText", palFallback.text)
    readonly property color cButton:     schemeColor("button", palFallback.button)
    readonly property color cButtonText: schemeColor("buttonText", palFallback.buttonText)
    // Akzentfarbe: eigene Akzentfarbe (falls gesetzt), sonst die Auswahlfarbe des Schemas
    readonly property color cAccent:     schemeColor("accent", schemeColor("selection", palFallback.highlight))
    readonly property color cAccentText: schemeColor("selectionText", palFallback.highlightedText)
    readonly property color cLink:       schemeColor("link", cAccent)
    readonly property color cPositive:   schemeColor("positive", "#27ae60")
    readonly property color cNeutral:    schemeColor("neutral", "#f67400")
    readonly property color cNegative:   schemeColor("negative", "#da4453")
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    readonly property bool busy: starting || stateName === "starting" || stateName === "loading_model"

    // ── Sprachen ──
    // Sprachnamen in der Systemsprache (über die KDE-Übersetzungen)
    readonly property var langNames: ({
        "en": i18n("English"),
        "de": i18n("German"),
        "af": i18n("Afrikaans"),
        "sq": i18n("Albanian"),
        "am": i18n("Amharic"),
        "ar": i18n("Arabic"),
        "az": i18n("Azerbaijani"),
        "eu": i18n("Basque"),
        "bn": i18n("Bengali"),
        "my": i18n("Burmese"),
        "bs": i18n("Bosnian"),
        "bg": i18n("Bulgarian"),
        "zh": i18n("Chinese"),
        "da": i18n("Danish"),
        "et": i18n("Estonian"),
        "fil": i18n("Filipino"),
        "fi": i18n("Finnish"),
        "fr": i18n("French"),
        "gl": i18n("Galician"),
        "ka": i18n("Georgian"),
        "el": i18n("Greek"),
        "gu": i18n("Gujarati"),
        "he": i18n("Hebrew"),
        "hi": i18n("Hindi"),
        "id": i18n("Indonesian"),
        "is": i18n("Icelandic"),
        "it": i18n("Italian"),
        "ja": i18n("Japanese"),
        "jv": i18n("Javanese"),
        "kn": i18n("Kannada"),
        "kk": i18n("Kazakh"),
        "ca": i18n("Catalan"),
        "km": i18n("Khmer"),
        "ko": i18n("Korean"),
        "hr": i18n("Croatian"),
        "lo": i18n("Lao"),
        "lv": i18n("Latvian"),
        "lt": i18n("Lithuanian"),
        "ms": i18n("Malay"),
        "ml": i18n("Malayalam"),
        "mt": i18n("Maltese"),
        "mr": i18n("Marathi"),
        "mk": i18n("Macedonian"),
        "mn": i18n("Mongolian"),
        "ne": i18n("Nepali"),
        "nl": i18n("Dutch"),
        "nb": i18n("Norwegian"),
        "ps": i18n("Pashto"),
        "fa": i18n("Persian"),
        "pl": i18n("Polish"),
        "pt": i18n("Portuguese"),
        "ro": i18n("Romanian"),
        "ru": i18n("Russian"),
        "sv": i18n("Swedish"),
        "sr": i18n("Serbian"),
        "si": i18n("Sinhala"),
        "sk": i18n("Slovak"),
        "sl": i18n("Slovenian"),
        "so": i18n("Somali"),
        "es": i18n("Spanish"),
        "su": i18n("Sundanese"),
        "sw": i18n("Swahili"),
        "ta": i18n("Tamil"),
        "te": i18n("Telugu"),
        "th": i18n("Thai"),
        "cs": i18n("Czech"),
        "tr": i18n("Turkish"),
        "uk": i18n("Ukrainian"),
        "hu": i18n("Hungarian"),
        "ur": i18n("Urdu"),
        "uz": i18n("Uzbek"),
        "vi": i18n("Vietnamese"),
        "cy": i18n("Welsh")
    })
    function langName(code) {
        if (code === "auto") return i18n("Automatic")
        return langNames[code] || Languages.nameOf(code)
    }

    readonly property string sourceName: langName(cfg.sourceLang)
    readonly property string targetName: langName(cfg.targetLang)
    readonly property string pairText: sourceName + " → " + targetName

    readonly property string stateText: {
        if (!installed) return i18n("Setup required")
        if (starting && !running) return i18n("Starting …")
        switch (stateName) {
        case "starting":      return i18n("Starting …")
        case "loading_model": return i18n("Loading speech model …")
        case "listening":     return i18n("Listening")
        case "recognizing":   return i18n("Translating …")
        case "speaking":      return i18n("Speaking")
        case "error":         return i18n("Error")
        default:              return i18n("Off")
        }
    }

    readonly property color stateColor: {
        if (stateName === "error") return cNegative
        if (busy) return cNeutral
        if (running) return cPositive
        return cDisabled
    }

    Plasmoid.icon: "audio-headset"
    Plasmoid.status: running ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    toolTipMainText: "AlloraVoice"
    toolTipSubText: running && dstText !== "" ? pairText + " · " + dstText : pairText + " · " + stateText

    preferredRepresentation: compactRepresentation
    compactRepresentation: CompactRepresentation {}
    fullRepresentation: FullRepresentation {}

    // ───────────── Sprachen & Stimmen ─────────────
    function setSource(code) {
        if (code === cfg.targetLang) cfg.targetLang = (cfg.sourceLang !== "auto" ? cfg.sourceLang : otherThan(code))
        cfg.sourceLang = code
    }
    function setTarget(code) {
        if (code === cfg.sourceLang) cfg.sourceLang = cfg.targetLang
        cfg.targetLang = code
    }
    function swapLanguages() {
        if (cfg.sourceLang === "auto") return
        var s = cfg.sourceLang
        cfg.sourceLang = cfg.targetLang
        cfg.targetLang = s
    }
    function otherThan(code) {
        for (var i = 0; i < Languages.list.length; ++i)
            if (Languages.list[i].code !== code) return Languages.list[i].code
        return code
    }

    function voiceMap() {
        try { return JSON.parse(cfg.voiceChoices || "{}") } catch (e) { return {} }
    }
    // ── Stimmen: Live-Liste von Microsoft (zwischengespeichert) ──
    property var allVoices: []
    property bool voicesLoaded: false
    readonly property var targetLanguageModel: Languages.comboModel(false, allVoices, favorites, langName, i18n("Automatically detect"))
    readonly property var sourceLanguageModel: Languages.comboModel(true, allVoices, favorites, langName, i18n("Automatically detect"))

    // ── Favoriten (angeheftete Sprachen) & Schnellauswahl (Sprachpaare) ──
    readonly property var favorites: parseJson(cfg.favoriteLangs, ["en", "de"])
    readonly property var quickPairs: parseJson(cfg.quickPairs, [])

    function parseJson(text, fallback) {
        try { var v = JSON.parse(text); return Array.isArray(v) ? v : fallback } catch (e) { return fallback }
    }
    function toggleFavorite(code) {
        var f = favorites.slice()
        var i = f.indexOf(code)
        if (i >= 0) f.splice(i, 1); else f.push(code)
        cfg.favoriteLangs = JSON.stringify(f)
    }
    function pairIndex(s, t) {
        for (var i = 0; i < quickPairs.length; ++i)
            if (quickPairs[i].s === s && quickPairs[i].t === t) return i
        return -1
    }
    function addCurrentPair() {
        if (pairIndex(cfg.sourceLang, cfg.targetLang) >= 0) return
        var p = quickPairs.slice()
        p.push({ s: cfg.sourceLang, t: cfg.targetLang })
        cfg.quickPairs = JSON.stringify(p)
    }
    function removePair(i) {
        var p = quickPairs.slice()
        p.splice(i, 1)
        cfg.quickPairs = JSON.stringify(p)
    }
    function applyPair(p) {
        cfg.sourceLang = p.s
        cfg.targetLang = p.t
    }

    function voicesFor(gender) {
        var list = Languages.voicesFor(cfg.targetLang, gender, allVoices, i18n("very natural"))
        if (!list.length)   // manche Sprachen haben nur weibliche oder nur männliche Stimmen
            list = Languages.voicesFor(cfg.targetLang, gender === "male" ? "female" : "male", allVoices, i18n("very natural"))
        return list
    }
    function loadVoices() {
        if (voicesLoaded) return
        ensureBackend(function() {
            api("GET", "/voices", null, function(r) {
                if (r && r.voices && r.voices.length) {
                    root.allVoices = r.voices
                    root.voicesLoaded = true
                    cfg.voiceCache = JSON.stringify(r.voices)
                }
            })
        })
    }

    function selectedVoice(gender) {
        var list = voicesFor(gender)
        var m = voiceMap()
        var v = m[cfg.targetLang] ? m[cfg.targetLang][gender] : ""
        for (var i = 0; i < list.length; ++i)
            if (list[i].value === v) return v
        return list.length ? list[0].value : ""
    }
    function setVoice(gender, value) {
        var m = voiceMap()
        if (!m[cfg.targetLang]) m[cfg.targetLang] = {}
        m[cfg.targetLang][gender] = value
        cfg.voiceChoices = JSON.stringify(m)
    }

    // ───────────── HTTP-Hilfsfunktionen ─────────────
    function api(method, path, body, cb) {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE) return
            var res = null
            if (x.status === 200) {
                try { res = JSON.parse(x.responseText) } catch (e) { res = null }
            }
            if (cb) cb(res)
        }
        x.open(method, apiBase + path)
        x.setRequestHeader("Content-Type", "application/json")
        x.send(body ? JSON.stringify(body) : null)
    }

    function configObject() {
        return {
            voice: selectedVoice(cfg.voiceGender),
            gender: cfg.voiceGender,
            rate: cfg.rate,
            pitch: cfg.pitch,
            ttsVolume: cfg.ttsVolume,
            originalVolume: cfg.originalVolume,
            duck: cfg.duckEnabled,
            duckLevel: cfg.duckLevel,
            adaptiveTempo: cfg.adaptiveTempo,
            syncMode: cfg.syncMode,
            maxLag: cfg.emergencyLag,
            mediaSync: cfg.mediaSync,
            recognizer: cfg.recognizer,
            responsiveness: cfg.responsiveness,
            translator: cfg.translator,
            deeplKey: cfg.deeplKey,
            source: Languages.forBackend(cfg.sourceLang),
            target: targetForBackend(),
            minLevel: cfg.sensitivity
        }
    }

    function targetForBackend() {
        var t = Languages.forBackend(cfg.targetLang)
        if (t) {
            var f = voicesFor("female"), m = voicesFor("male")
            t.fallback = { female: f.length ? f[f.length > 1 ? 1 : 0].value : "",
                           male: m.length ? m[m.length > 1 ? 1 : 0].value : "" }
        }
        return t
    }

    // Fehler kommen als Code vom Hintergrunddienst und werden hier in die Systemsprache übersetzt
    function localizedError(code, arg, fallback) {
        switch (code) {
        case "":                return fallback
        case "translate":       return i18n("Translation failed: %1", arg)
        case "translate_all":   return i18n("All translators are unreachable right now – check your internet connection.")
        case "whisper_missing": return i18n("Whisper is not installed – choose “Google Online” as recognition or run the setup again.")
        case "capture_ended":   return i18n("Audio capture stopped.")
        case "tts":             return i18n("Voice output failed: %1", arg)
        case "start":           return i18n("Could not start: %1", arg)
        case "no_sink":         return i18n("No audio output device found.")
        case "missing_program": return i18n("Missing program: %1", arg)
        default:                return fallback
        }
    }

    function applyStatus(s) {
        if (!s) {
            backendOnline = false
            running = false
            if (!starting) stateName = "offline"
            level = 0
            return
        }
        backendOnline = true
        running = s.running
        stateName = s.state
        level = s.level
        srcText = s.srcText
        dstText = s.dstText
        history = s.history
        errorText = localizedError(s.errorCode || "", s.errorArg || "", s.error || "")
        queueSize = s.queue
        lag = s.lag
        skipped = s.skipped
        mediaEvent = s.mediaEvent || ""
        backlog = s.backlog || 0
        tempo = s.tempo || 1
        mediaConnected = !!s.mediaConnected
        if (running || s.state === "error" || s.state === "idle") starting = false
    }

    function refresh() { api("GET", "/status", null, applyStatus) }
    function pushConfig() { if (backendOnline) api("POST", "/config", configObject(), null) }

    function setActive(on) {
        errorText = ""
        if (on) {
            if (!installed) { runSetup(); return }
            starting = true
            ensureBackend(function() { api("POST", "/start", configObject(), applyStatus) })
        } else {
            starting = false
            api("POST", "/stop", null, applyStatus)
        }
    }

    function testVoice() {
        var body = configObject()
        body.sample = Languages.sampleOf(cfg.targetLang)
        ensureBackend(function() { api("POST", "/test", body, null) })
    }

    function clearHistory() { api("POST", "/clear", null, applyStatus) }

    // ───────────── Backend starten ─────────────
    property var pendingCallback: null

    function launchBackend(cb) {
        pendingCallback = cb
        exec("bash '" + backendDir + "run.sh'")
        waitTimer.tries = 40
        waitTimer.start()
    }

    function ensureBackend(cb) {
        api("GET", "/ping", null, function(r) {
            if (r && r.version === root.backendVersion) { backendOnline = true; cb(); return }
            if (r) {
                // ältere Version läuft noch → beenden und neu starten
                api("POST", "/quit", null, function() {
                    restartDelay.cb = cb
                    restartDelay.start()
                })
                return
            }
            launchBackend(cb)
        })
    }

    Timer {
        id: restartDelay
        property var cb: null
        interval: 800
        onTriggered: root.launchBackend(cb)
    }

    Timer {
        id: waitTimer
        property int tries: 0
        interval: 500
        repeat: true
        onTriggered: {
            api("GET", "/ping", null, function(r) {
                if (!waitTimer.running) return
                if (r) {
                    waitTimer.stop()
                    backendOnline = true
                    var cb = root.pendingCallback
                    root.pendingCallback = null
                    if (cb) cb()
                } else if (--waitTimer.tries <= 0) {
                    waitTimer.stop()
                    root.starting = false
                    root.errorText = i18n("Background service does not start. Log: ~/.local/share/alloravoice/backend.log")
                }
            })
        }
    }

    // ───────────── Shell-Befehle ─────────────
    readonly property string colorsCmd: "bash '" + backendDir + "colors.sh'"
    function readColors() { exec(colorsCmd) }

    readonly property string installCheckCmd:
        "test -x \"$HOME/.local/share/alloravoice/venv/bin/python\" -o -x \"$HOME/.local/share/voxa/venv/bin/python\" && echo yes || echo no"

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            var out = (data["stdout"] || "").trim()
            if (sourceName === root.colorsCmd) {
                var sc = {}
                out.split("\n").forEach(function(line) {
                    var i = line.indexOf("=")
                    if (i > 0 && line.substring(i + 1).trim() !== "") sc[line.substring(0, i)] = line.substring(i + 1).trim()
                })
                root.scheme = sc
            }
            if (sourceName === root.installCheckCmd) {
                root.installed = (out === "yes")
                if (root.installed && root.expanded) root.loadVoices()
            }
            disconnectSource(sourceName)
        }
    }

    function exec(cmd) { executable.connectSource(cmd) }
    function checkInstalled() { exec(installCheckCmd) }
    function runSetup() { exec("konsole --hold -e bash '" + backendDir + "setup.sh'") }

    // ───────────── Polling & Konfiguration ─────────────
    Timer {
        interval: (root.running || root.expanded || root.starting) ? 350 : 4000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        id: configPush
        interval: 150
        onTriggered: root.pushConfig()
    }

    Connections {
        target: Plasmoid.configuration
        function onValueChanged(key, value) { configPush.restart() }
    }

    // beim Öffnen neu einlesen – so greift ein geändertes Farbschema sofort
    onExpandedChanged: if (expanded) { checkInstalled(); readColors() }
    Component.onCompleted: {
        try { allVoices = JSON.parse(cfg.voiceCache || "[]") } catch (e) { allVoices = [] }
        checkInstalled()
        readColors()
    }

    // ───────────── Untertitel-Overlay ─────────────
    SubtitleOverlay {
        visible: root.cfg.overlay && root.running && root.dstText !== ""
        translatedText: root.dstText
        originalText: root.cfg.overlayShowOriginal ? root.srcText : ""
    }
}
