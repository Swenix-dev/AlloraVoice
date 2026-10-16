.pragma library
/*
 * SPDX-FileCopyrightText: 2026 SeaQ
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
/*
 * AlloraVoice – Sprachliste
 * ─────────────────────────────────────────────────────────────────────────────
 * Alle Sprachen, die Spracherkennung (Whisper), Übersetzung (Google) und
 * Microsoft-Neural-Stimmen gemeinsam beherrschen.
 *
 * Die Stimmen selbst lädt AlloraVoice live von Microsoft – dadurch sind immer
 * alle verfügbaren Stimmen dabei, auch neue.
 *
 * Neue Sprache hinzufügen: eine Zeile L(...) unten anhängen und den Namen in
 * main.qml (langNames) mit i18n() eintragen, damit er übersetzt wird.
 *   L(code, English name, Whisper-Code, Google-Sprach-Locale, Google-Übersetzer-Code,
 *     DeepL-Zielsprache oder "", Stimmen-Präfix)
 */
function L(code, name, whisper, stt, google, deepl, voicePrefix) {
    var o = { code: code, name: name, whisper: whisper, stt: stt, google: google, voicePrefix: voicePrefix }
    if (deepl) {
        o.deepl = deepl
        o.deeplSource = deepl.split("-")[0]
    }
    return o
}

var all = [
    L("en",  "English",           "en", "en-US",  "en",    "EN-US", "en-"),
    L("de",  "German",            "de", "de-DE",  "de",    "DE",    "de-"),
    L("af",  "Afrikaans",         "af", "af-ZA",  "af",    "",      "af-"),
    L("sq",  "Albanian",          "sq", "sq-AL",  "sq",    "",      "sq-"),
    L("am",  "Amharic",           "am", "am-ET",  "am",    "",      "am-"),
    L("ar",  "Arabic",            "ar", "ar-SA",  "ar",    "AR",    "ar-"),
    L("az",  "Azerbaijani",       "az", "az-AZ",  "az",    "",      "az-"),
    L("eu",  "Basque",            "eu", "eu-ES",  "eu",    "",      "eu-"),
    L("bn",  "Bengali",           "bn", "bn-IN",  "bn",    "",      "bn-"),
    L("my",  "Burmese",           "my", "my-MM",  "my",    "",      "my-"),
    L("bs",  "Bosnian",           "bs", "bs-BA",  "bs",    "",      "bs-"),
    L("bg",  "Bulgarian",         "bg", "bg-BG",  "bg",    "BG",    "bg-"),
    L("zh",  "Chinese",           "zh", "zh-CN",  "zh-CN", "ZH",    "zh-"),
    L("da",  "Danish",            "da", "da-DK",  "da",    "DA",    "da-"),
    L("et",  "Estonian",          "et", "et-EE",  "et",    "ET",    "et-"),
    L("fil", "Filipino",          "tl", "fil-PH", "tl",    "",      "fil-"),
    L("fi",  "Finnish",           "fi", "fi-FI",  "fi",    "FI",    "fi-"),
    L("fr",  "French",            "fr", "fr-FR",  "fr",    "FR",    "fr-"),
    L("gl",  "Galician",          "gl", "gl-ES",  "gl",    "",      "gl-"),
    L("ka",  "Georgian",          "ka", "ka-GE",  "ka",    "",      "ka-"),
    L("el",  "Greek",             "el", "el-GR",  "el",    "EL",    "el-"),
    L("gu",  "Gujarati",          "gu", "gu-IN",  "gu",    "",      "gu-"),
    L("he",  "Hebrew",            "he", "he-IL",  "iw",    "",      "he-"),
    L("hi",  "Hindi",             "hi", "hi-IN",  "hi",    "",      "hi-"),
    L("id",  "Indonesian",        "id", "id-ID",  "id",    "ID",    "id-"),
    L("is",  "Icelandic",         "is", "is-IS",  "is",    "",      "is-"),
    L("it",  "Italian",           "it", "it-IT",  "it",    "IT",    "it-"),
    L("ja",  "Japanese",          "ja", "ja-JP",  "ja",    "JA",    "ja-"),
    L("jv",  "Javanese",          "jw", "jv-ID",  "jw",    "",      "jv-"),
    L("kn",  "Kannada",           "kn", "kn-IN",  "kn",    "",      "kn-"),
    L("kk",  "Kazakh",            "kk", "kk-KZ",  "kk",    "",      "kk-"),
    L("ca",  "Catalan",           "ca", "ca-ES",  "ca",    "",      "ca-"),
    L("km",  "Khmer",             "km", "km-KH",  "km",    "",      "km-"),
    L("ko",  "Korean",            "ko", "ko-KR",  "ko",    "KO",    "ko-"),
    L("hr",  "Croatian",          "hr", "hr-HR",  "hr",    "",      "hr-"),
    L("lo",  "Lao",               "lo", "lo-LA",  "lo",    "",      "lo-"),
    L("lv",  "Latvian",           "lv", "lv-LV",  "lv",    "LV",    "lv-"),
    L("lt",  "Lithuanian",        "lt", "lt-LT",  "lt",    "LT",    "lt-"),
    L("ms",  "Malay",             "ms", "ms-MY",  "ms",    "",      "ms-"),
    L("ml",  "Malayalam",         "ml", "ml-IN",  "ml",    "",      "ml-"),
    L("mt",  "Maltese",           "mt", "mt-MT",  "mt",    "",      "mt-"),
    L("mr",  "Marathi",           "mr", "mr-IN",  "mr",    "",      "mr-"),
    L("mk",  "Macedonian",        "mk", "mk-MK",  "mk",    "",      "mk-"),
    L("mn",  "Mongolian",         "mn", "mn-MN",  "mn",    "",      "mn-"),
    L("ne",  "Nepali",            "ne", "ne-NP",  "ne",    "",      "ne-"),
    L("nl",  "Dutch",             "nl", "nl-NL",  "nl",    "NL",    "nl-"),
    L("nb",  "Norwegian",         "no", "nb-NO",  "no",    "NB",    "nb-"),
    L("ps",  "Pashto",            "ps", "ps-AF",  "ps",    "",      "ps-"),
    L("fa",  "Persian",           "fa", "fa-IR",  "fa",    "",      "fa-"),
    L("pl",  "Polish",            "pl", "pl-PL",  "pl",    "PL",    "pl-"),
    L("pt",  "Portuguese",        "pt", "pt-BR",  "pt",    "PT-BR", "pt-"),
    L("ro",  "Romanian",          "ro", "ro-RO",  "ro",    "RO",    "ro-"),
    L("ru",  "Russian",           "ru", "ru-RU",  "ru",    "RU",    "ru-"),
    L("sv",  "Swedish",           "sv", "sv-SE",  "sv",    "SV",    "sv-"),
    L("sr",  "Serbian",           "sr", "sr-RS",  "sr",    "",      "sr-"),
    L("si",  "Sinhala",           "si", "si-LK",  "si",    "",      "si-"),
    L("sk",  "Slovak",            "sk", "sk-SK",  "sk",    "SK",    "sk-"),
    L("sl",  "Slovenian",         "sl", "sl-SI",  "sl",    "SL",    "sl-"),
    L("so",  "Somali",            "so", "so-SO",  "so",    "",      "so-"),
    L("es",  "Spanish",           "es", "es-ES",  "es",    "ES",    "es-"),
    L("su",  "Sundanese",         "su", "su-ID",  "su",    "",      "su-"),
    L("sw",  "Swahili",           "sw", "sw-KE",  "sw",    "",      "sw-"),
    L("ta",  "Tamil",             "ta", "ta-IN",  "ta",    "",      "ta-"),
    L("te",  "Telugu",            "te", "te-IN",  "te",    "",      "te-"),
    L("th",  "Thai",              "th", "th-TH",  "th",    "",      "th-"),
    L("cs",  "Czech",             "cs", "cs-CZ",  "cs",    "CS",    "cs-"),
    L("tr",  "Turkish",           "tr", "tr-TR",  "tr",    "TR",    "tr-"),
    L("uk",  "Ukrainian",         "uk", "uk-UA",  "uk",    "UK",    "uk-"),
    L("hu",  "Hungarian",         "hu", "hu-HU",  "hu",    "HU",    "hu-"),
    L("ur",  "Urdu",              "ur", "ur-PK",  "ur",    "",      "ur-"),
    L("uz",  "Uzbek",             "uz", "uz-UZ",  "uz",    "",      "uz-"),
    L("vi",  "Vietnamese",        "vi", "vi-VN",  "vi",    "",      "vi-"),
    L("cy",  "Welsh",             "cy", "cy-GB",  "cy",    "",      "cy-")
]

// Handverlesene Stimmen, solange die Live-Liste noch nicht geladen ist
var curated = {
    en: {
        sample: "Hello! This is how I sound when I translate for you.",
        female: ["en-US-AvaMultilingualNeural", "en-US-EmmaMultilingualNeural", "en-US-JennyNeural", "en-GB-SoniaNeural"],
        male:   ["en-US-AndrewMultilingualNeural", "en-US-BrianMultilingualNeural", "en-US-GuyNeural", "en-GB-RyanNeural"]
    },
    de: {
        sample: "Hallo! So klinge ich, wenn ich für dich übersetze.",
        female: ["de-DE-SeraphinaMultilingualNeural", "de-DE-KatjaNeural", "de-DE-AmalaNeural", "de-AT-IngridNeural", "de-CH-LeniNeural"],
        male:   ["de-DE-FlorianMultilingualNeural", "de-DE-ConradNeural", "de-DE-KillianNeural", "de-AT-JonasNeural", "de-CH-JanNeural"]
    }
}

var list = all   // Rückwärtskompatibilität

// Sortierschlüssel: Umlaute & Akzente wie Grundbuchstaben (Ä = A, É = E …)
function sortKey(name) {
    return String(name).toLowerCase()
        .replace(/[äáàâã]/g, "a").replace(/[öóòôõ]/g, "o").replace(/[üúùû]/g, "u")
        .replace(/[éèêë]/g, "e").replace(/[íìîï]/g, "i").replace(/ß/g, "ss").replace(/ç/g, "c").replace(/ñ/g, "n")
}

function byCode(code) {
    for (var i = 0; i < all.length; ++i)
        if (all[i].code === code) return all[i]
    return null
}

// Englischer Name – die Anzeige in der Systemsprache übernimmt main.qml (i18n)
function nameOf(code) {
    if (code === "auto") return "Automatic"
    var l = byCode(code)
    return l ? l.name : code
}

function sampleOf(code) {
    return curated[code] ? curated[code].sample : ""
}

// Nur die Felder, die der Hintergrunddienst braucht
function forBackend(code) {
    if (code === "auto") return { code: "auto" }
    var l = byCode(code)
    if (!l) return null
    var o = { code: l.code, whisper: l.whisper, stt: l.stt, google: l.google }
    if (l.deepl) { o.deepl = l.deepl; o.deeplSource = l.deeplSource }
    return o
}

// ── Stimmen: Live-Liste von Microsoft [{n: ShortName, g: Gender, l: Locale}] ──
function voiceLabel(shortName, locale, naturalLabel) {
    var name = shortName.substring(locale.length + 1).replace(/Neural$/, "")
    var multi = name.indexOf("Multilingual") >= 0
    name = name.replace("Multilingual", "")
    var region = locale.split("-").slice(1).join("-")
    return name + " · " + region + (multi ? " · " + naturalLabel : "")
}

function localeOf(shortName) {
    // "de-DE-SeraphinaMultilingualNeural" → "de-DE"; "zh-CN-liaoning-XiaobeiNeural" → "zh-CN-liaoning"
    var parts = shortName.split("-")
    return parts.slice(0, parts.length - 1).join("-")
}

function voicesFor(code, gender, liveVoices, naturalLabel) {
    var l = byCode(code)
    if (!l) return []
    naturalLabel = naturalLabel || "very natural"
    var g = gender === "male" ? "Male" : "Female"
    var out = []
    if (liveVoices && liveVoices.length) {
        var main = l.stt
        var found = liveVoices.filter(function(v) { return v.g === g && v.l.indexOf(l.voicePrefix) === 0 })
        found.sort(function(a, b) {
            var am = a.n.indexOf("Multilingual") >= 0 ? 0 : 1, bm = b.n.indexOf("Multilingual") >= 0 ? 0 : 1
            if (am !== bm) return am - bm
            var ap = a.l === main ? 0 : 1, bp = b.l === main ? 0 : 1
            if (ap !== bp) return ap - bp
            if (a.l !== b.l) return a.l < b.l ? -1 : 1
            return a.n < b.n ? -1 : 1
        })
        for (var i = 0; i < found.length; ++i)
            out.push({ text: voiceLabel(found[i].n, found[i].l, naturalLabel), value: found[i].n })
    }
    if (!out.length && curated[code]) {
        var names = curated[code][gender === "male" ? "male" : "female"]
        for (var j = 0; j < names.length; ++j)
            out.push({ text: voiceLabel(names[j], localeOf(names[j]), naturalLabel), value: names[j] })
    }
    return out
}

function hasVoices(code, liveVoices) {
    return voicesFor(code, "female", liveVoices).length > 0 || voicesFor(code, "male", liveVoices).length > 0
}

// Auswahlliste: zuerst die Favoriten (in der Reihenfolge, in der sie markiert wurden),
// danach alle übrigen Sprachen alphabetisch – nach dem Namen in der Systemsprache.
//   nameFn(code) liefert den übersetzten Namen, autoLabel den Text für „Automatisch erkennen“
function comboModel(withAuto, liveVoices, favorites, nameFn, autoLabel) {
    favorites = favorites || []
    nameFn = nameFn || nameOf
    var m = withAuto ? [{ text: autoLabel || "Automatically detect", value: "auto", fav: false, lastFav: false }] : []
    function usable(code) {
        // als Zielsprache nur Sprachen, für die es auch eine Stimme gibt
        return withAuto || hasVoices(code, liveVoices)
    }
    var favs = []
    for (var f = 0; f < favorites.length; ++f) {
        var l = byCode(favorites[f])
        if (l && usable(l.code)) favs.push({ text: nameFn(l.code), value: l.code, fav: true, lastFav: false })
    }
    if (favs.length) favs[favs.length - 1].lastFav = true
    var rest = []
    for (var i = 0; i < all.length; ++i) {
        if (favorites.indexOf(all[i].code) >= 0 || !usable(all[i].code)) continue
        rest.push({ text: nameFn(all[i].code), value: all[i].code, fav: false, lastFav: false })
    }
    rest.sort(function(a, b) {
        var ka = sortKey(a.text), kb = sortKey(b.text)
        return ka < kb ? -1 : (ka > kb ? 1 : 0)
    })
    return m.concat(favs).concat(rest)
}
