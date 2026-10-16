# Changelog

## 2.5.3
- Popup height is locked to its content (minimum = maximum), so Plasma can no longer show a remembered, taller popup with empty space

## 2.5.2
- Popup height now follows the content of the selected tab – no empty space below the sliders
- Horizontal scrollbar removed; a vertical one only appears when a tab really doesn't fit

## 2.5.1
- Popup background, text and accent colors are read directly from the **KDE color scheme** (`kdeglobals`) instead of the Plasma style – re-read every time the popup opens
- Sliders use the scheme's **accent color**

## 2.5.0
- The interface now follows the **system language** (System Settings → Region & Language) via KDE's gettext translations
- English is the source language, German translation included – other languages can be added as `po/<lang>.po`
- Language names in the From/To lists are translated and sorted alphabetically in the system language
- Error messages from the background service are translated as well; the setup window speaks German or English

## 2.4.0
- Languages sorted strictly alphabetically
- **Quick select**: save language pairs (e.g. English → German) and switch with one click
- **Pin languages** with ★ – they stay at the top of the “From” / “To” lists

## 2.3.0
- Popup uses the colors of the **system color scheme** (no Plasma-style blur)
- **73 languages**, all Microsoft Neural voices loaded live (cached for 7 days)
- “Listen” plays a test sentence in the selected target language
- DeepL is only used for languages DeepL supports – everything else falls back to Google automatically

## 2.2.0
- New tempo control: sentences are **never cut off** any more
- Speaking rate is planned ahead per sentence; playback speeds up smoothly (up to 1.35×, pitch preserved) when sentences queue up
- Waiting sentences are merged instead of dropped; emergency jump only between sentences

## 2.1.0
- Detects **seeking and pausing** in YouTube, Udemy, VLC … (MPRIS) and starts over at the new position
- Voice is **streamed** – playback starts with the first audio chunk
- Shorter speech segments, faster Whisper threading

## 2.0.0
- Renamed from *Voxa* to **AlloraVoice**
- Language pair selection (From → To) with swap button
- Sync mode, adaptive tempo, delay indicator
- Headset icon in all states, theme-colored UI

## 1.1.0
- Translator chain with automatic fallback (Google → Google 2 → MyMemory), rate limiting and cache

## 1.0.0
- First version: system-wide capture via PipeWire, Whisper, Google/DeepL, Microsoft Neural voices, ducking, subtitles overlay, history
