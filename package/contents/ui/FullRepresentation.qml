/*
 * SPDX-FileCopyrightText: 2026 SeaQ
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import "languages.js" as Languages

PlasmaExtras.Representation {
    id: full

    Layout.minimumWidth: Kirigami.Units.gridUnit * 22
    Layout.preferredWidth: Kirigami.Units.gridUnit * 24
    // Höhe = genau der Inhalt (Kopf + gewählter Reiter), höchstens 46 Rastereinheiten.
    // Mindest- und Höchstwert sind gleich, damit Plasma keine gemerkte, größere Popup-Höhe
    // mit leerem Raum anzeigt.
    readonly property real contentHeightHint: Math.min(
        (header ? header.implicitHeight : 0) + mainCol.implicitHeight + topPadding + bottomPadding,
        Kirigami.Units.gridUnit * 46)
    Layout.minimumHeight: contentHeightHint
    Layout.preferredHeight: contentHeightHint
    Layout.maximumHeight: contentHeightHint

    collapseMarginsHint: true

    // ── Farben aus dem System-Farbschema (Systemeinstellungen → Farben),
    //    nicht aus dem durchsichtigen Plasma-Stil ──

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.backgroundColor: root.cWindow
    Kirigami.Theme.alternateBackgroundColor: root.cWindowAlt
    Kirigami.Theme.textColor: root.cText
    Kirigami.Theme.disabledTextColor: root.cDisabled
    Kirigami.Theme.highlightColor: root.cAccent
    Kirigami.Theme.highlightedTextColor: root.cAccentText
    Kirigami.Theme.linkColor: root.cLink
    Kirigami.Theme.focusColor: root.cAccent
    Kirigami.Theme.hoverColor: root.cAccent
    Kirigami.Theme.positiveTextColor: root.cPositive
    Kirigami.Theme.neutralTextColor: root.cNeutral
    Kirigami.Theme.negativeTextColor: root.cNegative

    // deckender Hintergrund statt Blur
    background: Rectangle {
        color: root.cWindow
        radius: Kirigami.Units.cornerRadius
    }

    readonly property var cfg: Plasmoid.configuration
    readonly property bool isOn: root.running || root.starting

    function indexOf(list, value) {
        for (var i = 0; i < list.length; ++i)
            if (list[i].value === value) return i
        return 0
    }
    function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    readonly property var recognizerOptions: [
        { text: i18n("Whisper Tiny – fastest"),             value: "whisper-tiny" },
        { text: i18n("Whisper Base – balanced (recommended)"),     value: "whisper-base" },
        { text: i18n("Whisper Small – more accurate, more CPU"),         value: "whisper-small" },
        { text: i18n("Google Online – fast, needs internet"), value: "google" }
    ]
    readonly property var responsivenessOptions: [
        { text: i18n("Fast – short segments, little delay"), value: "fast" },
        { text: i18n("Balanced (recommended)"),                   value: "balanced" },
        { text: i18n("Precise – whole sentences, more context"),        value: "precise" }
    ]
    readonly property var translatorOptions: [
        { text: i18n("Google Translate – free"),          value: "google" },
        { text: i18n("DeepL – best quality (API key)"), value: "deepl" }
    ]
    readonly property var sourceModel: root.sourceLanguageModel
    readonly property var targetModel: root.targetLanguageModel

    // ═══════════════════════ Kopfbereich ═══════════════════════
    header: PlasmaExtras.PlasmoidHeading {
        background: Item {
            Kirigami.Separator {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                color: root.alpha(root.cText, 0.15)
            }
        }
        contentItem: RowLayout {
            spacing: Kirigami.Units.largeSpacing

            Item {
                Layout.preferredWidth: Kirigami.Units.iconSizes.large
                Layout.preferredHeight: Kirigami.Units.iconSizes.large

                Rectangle {   // pulsierender Ring = Audiopegel
                    anchors.centerIn: parent
                    width: parent.width * 0.9 + root.level * Kirigami.Units.gridUnit
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: Kirigami.Theme.highlightColor
                    opacity: root.running ? 0.2 + root.level * 0.6 : 0
                    Behavior on width { NumberAnimation { duration: 90 } }
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.medium
                    height: width
                    source: "audio-headset"
                }
            }

            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                Kirigami.Heading {
                    level: 3
                    text: "AlloraVoice"
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Rectangle {
                        width: Kirigami.Units.smallSpacing * 2
                        height: width
                        radius: width / 2
                        color: root.stateColor
                    }
                    PlasmaComponents3.Label {
                        text: root.pairText + " · " + root.stateText
                        opacity: 0.75
                        font: Kirigami.Theme.smallFont
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
            }

            PlasmaComponents3.BusyIndicator {
                visible: root.busy
                running: visible
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            }

            PlasmaComponents3.Switch {
                checked: full.isOn
                onToggled: root.setActive(checked)
                PlasmaComponents3.ToolTip.text: i18n("Switch translation on/off (middle-click on the icon works too)")
                PlasmaComponents3.ToolTip.visible: hovered
            }
        }
    }

    // ═══════════════════════ Inhalt ═══════════════════════
    contentItem: ColumnLayout {
        id: mainCol
        spacing: Kirigami.Units.largeSpacing

        // ── Schnellauswahl: gespeicherte Sprachpaare mit einem Klick ──
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            Layout.topMargin: Kirigami.Units.largeSpacing
            spacing: 2

            PlasmaComponents3.Label { text: i18n("Quick select"); font: Kirigami.Theme.smallFont; opacity: 0.7 }
            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: root.quickPairs
                    PlasmaComponents3.Button {
                        readonly property bool active: modelData.s === full.cfg.sourceLang && modelData.t === full.cfg.targetLang
                        checkable: true
                        checked: active
                        text: root.langName(modelData.s) + " → " + root.langName(modelData.t)
                        onClicked: {
                            root.applyPair(modelData)
                            checked = Qt.binding(() => active)
                        }
                        PlasmaComponents3.ToolTip.text: i18n("Click: select · Right-click: remove from quick select")
                        PlasmaComponents3.ToolTip.visible: hovered
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            onClicked: root.removePair(index)
                        }
                    }
                }

                PlasmaComponents3.ToolButton {
                    visible: root.pairIndex(full.cfg.sourceLang, full.cfg.targetLang) < 0
                    icon.name: "list-add"
                    text: i18n("Save current pair")
                    onClicked: root.addCurrentPair()
                }
            }
        }

        // ── Sprachauswahl: Von → Nach (★ = oben anheften) ──
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 2
                PlasmaComponents3.Label { text: i18n("From"); font: Kirigami.Theme.smallFont; opacity: 0.7 }
                LanguageCombo {
                    Layout.fillWidth: true
                    model: full.sourceModel
                    current: full.cfg.sourceLang
                    onPicked: code => root.setSource(code)
                }
            }

            PlasmaComponents3.ToolButton {
                Layout.alignment: Qt.AlignBottom
                text: "⇄"
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
                enabled: full.cfg.sourceLang !== "auto"
                onClicked: root.swapLanguages()
                PlasmaComponents3.ToolTip.text: i18n("Swap languages")
                PlasmaComponents3.ToolTip.visible: hovered
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 2
                PlasmaComponents3.Label { text: i18n("To"); font: Kirigami.Theme.smallFont; opacity: 0.7 }
                LanguageCombo {
                    Layout.fillWidth: true
                    model: full.targetModel
                    current: full.cfg.targetLang
                    onPicked: code => root.setTarget(code)
                }
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            visible: !root.installed
            type: Kirigami.MessageType.Information
            text: i18n("One-time setup required: voices, translator and speech recognition will be installed (about 5 minutes).")
            actions: [
                Kirigami.Action {
                    text: i18n("Set up now")
                    icon.name: "run-install"
                    onTriggered: root.runSetup()
                }
            ]
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            visible: root.errorText !== ""
            type: Kirigami.MessageType.Warning
            text: root.errorText
            showCloseButton: true
        }

        // ── Live-Karte (Rahmen aus dem Plasma-Stil) ──
        Item {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            implicitHeight: liveCol.implicitHeight + Kirigami.Units.largeSpacing * 2

            Rectangle {
                anchors.fill: parent
                radius: Kirigami.Units.cornerRadius * 2
                color: root.cView
                border.width: 1
                border.color: root.running ? root.alpha(root.cAccent, 0.6)
                                           : root.alpha(root.cText, 0.15)
                Behavior on border.color { ColorAnimation { duration: Kirigami.Units.longDuration } }
            }

            ColumnLayout {
                id: liveCol
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents3.Label {
                        text: i18n("LIVE")
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: root.running ? Kirigami.Theme.highlightColor : Kirigami.Theme.disabledTextColor
                    }
                    PlasmaComponents3.Label {
                        visible: root.running && root.lag > 0
                        text: i18n("Delay %1 s", root.lag.toLocaleString(Qt.locale(), "f", 1))
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                        color: root.backlog > full.cfg.emergencyLag * 0.6 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                    }
                    PlasmaComponents3.Label {
                        visible: root.running && root.tempo > 1.02 && root.mediaEvent === ""
                        text: i18n("· Tempo %1×", root.tempo.toLocaleString(Qt.locale(), "f", 2))
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                    }
                    PlasmaComponents3.Label {
                        visible: root.running && full.cfg.syncMode && root.skipped > 0 && root.mediaEvent === ""
                        text: i18n("· %1 skipped", root.skipped)
                        font: Kirigami.Theme.smallFont
                        opacity: 0.6
                    }
                    PlasmaComponents3.Label {
                        visible: root.running && root.mediaEvent !== ""
                        text: root.mediaEvent === "pause" ? i18n("⏸ Paused – voice stopped")
                                                          : i18n("↻ Jumped to the new position")
                        font: Kirigami.Theme.smallFont
                        color: Kirigami.Theme.highlightColor
                    }
                    Item { Layout.fillWidth: true }
                    // Pegelanzeige
                    Row {
                        spacing: 2
                        Repeater {
                            model: 14
                            Rectangle {
                                readonly property real shape: 0.45 + 0.55 * Math.abs(Math.sin(index * 1.7 + 0.6))
                                width: 3
                                height: Kirigami.Units.gridUnit * 0.9
                                radius: 1.5
                                color: full.tint(Kirigami.Theme.textColor, 0.12)
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    radius: 1.5
                                    height: parent.height * Math.min(1, root.level * 1.8 * parent.shape)
                                    color: Kirigami.Theme.highlightColor
                                    Behavior on height { NumberAnimation { duration: 80 } }
                                }
                            }
                        }
                    }
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    visible: root.srcText !== ""
                    text: root.srcText
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.italic: true
                    opacity: 0.6
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: root.dstText !== "" ? root.dstText
                          : (root.running ? i18n("Waiting for speech (%1) …", root.sourceName)
                                          : i18n("Switch translation on above and play a video – YouTube, Udemy or anything else."))
                    wrapMode: Text.WordWrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    font.pointSize: root.dstText !== "" ? Kirigami.Theme.defaultFont.pointSize * 1.25 : Kirigami.Theme.defaultFont.pointSize
                    font.weight: root.dstText !== "" ? Font.DemiBold : Font.Normal
                    opacity: root.dstText !== "" ? 1 : 0.6
                }
            }
        }

        // ── Reiter ──
        PlasmaComponents3.TabBar {
            id: tabs
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            PlasmaComponents3.TabButton { text: i18n("Voice"); icon.name: "audio-input-microphone" }
            PlasmaComponents3.TabButton { text: i18n("Sound"); icon.name: "audio-volume-high" }
            PlasmaComponents3.TabButton { text: i18n("Sync"); icon.name: "configure" }
            PlasmaComponents3.TabButton { text: i18n("History"); icon.name: "view-history" }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.maximumHeight: Layout.preferredHeight
            // Höhe passt sich dem Inhalt des gewählten Reiters an – kein leerer Raum unten
            Layout.preferredHeight: [voiceCol.implicitHeight, soundCol.implicitHeight,
                                     syncCol.implicitHeight, Kirigami.Units.gridUnit * 16][currentIndex]
            Layout.minimumHeight: Kirigami.Units.gridUnit * 8
            currentIndex: tabs.currentIndex

            // ════════ Stimme ════════
            PlasmaComponents3.ScrollView {
                contentWidth: availableWidth
                // kein waagerechter Scrollbalken – senkrecht nur, wenn der Platz wirklich nicht reicht
                PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff
                ColumnLayout {
                    id: voiceCol
                    width: parent.width
                    spacing: Kirigami.Units.largeSpacing

                    Item { implicitHeight: 1 }

                    // Geschlecht – mit etwas Abstand zwischen den beiden Knöpfen
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.largeSpacing
                        Layout.rightMargin: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.largeSpacing
                        Repeater {
                            model: [
                                { key: "female", label: i18n("Female voice"), icon: "user-female" },
                                { key: "male",   label: i18n("Male voice"), icon: "user-male" }
                            ]
                            PlasmaComponents3.Button {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                checkable: true
                                checked: full.cfg.voiceGender === modelData.key
                                text: modelData.label
                                icon.name: modelData.icon
                                onClicked: full.cfg.voiceGender = modelData.key
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.largeSpacing
                        Layout.rightMargin: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing
                        PlasmaComponents3.Label { text: i18n("Speaker (%1)", root.targetName) }
                        RowLayout {
                            Layout.fillWidth: true
                            PlasmaComponents3.ComboBox {
                                id: voiceCombo
                                Layout.fillWidth: true
                                readonly property var voices: root.voicesFor(full.cfg.voiceGender)
                                model: voices
                                textRole: "text"
                                valueRole: "value"
                                currentIndex: full.indexOf(voices, root.selectedVoice(full.cfg.voiceGender))
                                onActivated: idx => root.setVoice(full.cfg.voiceGender, voices[idx].value)
                            }
                            PlasmaComponents3.Button {
                                icon.name: "media-playback-start"
                                text: i18n("Listen")
                                enabled: root.installed
                                onClicked: root.testVoice()
                            }
                        }
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: i18n("Microsoft neural voices – they sound like real speakers. “Very natural” marks the newest models.")
                            wrapMode: Text.WordWrap
                            font: Kirigami.Theme.smallFont
                            opacity: 0.6
                        }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.largeSpacing
                        Layout.rightMargin: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.largeSpacing

                        SettingSlider {
                            label: i18n("Base speaking rate")
                            from: -50; to: 100; stepSize: 5
                            signedValue: true
                            resetValue: 0
                            value: full.cfg.rate
                            onMoved: v => full.cfg.rate = Math.round(v)
                        }
                        SettingSlider {
                            label: i18n("Pitch")
                            unit: "Hz"
                            from: -30; to: 30; stepSize: 2
                            signedValue: true
                            resetValue: 0
                            value: full.cfg.pitch
                            onMoved: v => full.cfg.pitch = Math.round(v)
                        }
                        SettingSlider {
                            label: i18n("Voice volume")
                            from: 0; to: 150; stepSize: 5
                            resetValue: 100
                            value: full.cfg.ttsVolume
                            onMoved: v => full.cfg.ttsVolume = Math.round(v)
                        }
                    }
                    Item { implicitHeight: Kirigami.Units.smallSpacing }
                }
            }

            // ════════ Ton ════════
            PlasmaComponents3.ScrollView {
                contentWidth: availableWidth
                // kein waagerechter Scrollbalken – senkrecht nur, wenn der Platz wirklich nicht reicht
                PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff
                ColumnLayout {
                    id: soundCol
                    width: parent.width
                    spacing: Kirigami.Units.largeSpacing

                    Item { implicitHeight: 1 }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.largeSpacing
                        Layout.rightMargin: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.largeSpacing

                        SettingSlider {
                            label: i18n("Original volume")
                            from: 0; to: 100; stepSize: 5
                            resetValue: 100
                            value: full.cfg.originalVolume
                            onMoved: v => full.cfg.originalVolume = Math.round(v)
                        }

                        Kirigami.Separator { Layout.fillWidth: true }

                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                PlasmaComponents3.Label { text: i18n("Lower the original while speaking") }
                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: i18n("Like a dubbed film: music and sounds stay quietly audible")
                                    wrapMode: Text.WordWrap
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.6
                                }
                            }
                            PlasmaComponents3.Switch {
                                checked: full.cfg.duckEnabled
                                onToggled: full.cfg.duckEnabled = checked
                            }
                        }

                        SettingSlider {
                            enabled: full.cfg.duckEnabled
                            opacity: enabled ? 1 : 0.5
                            label: i18n("Lower original to")
                            from: 0; to: 80; stepSize: 5
                            resetValue: 20
                            value: full.cfg.duckLevel
                            onMoved: v => full.cfg.duckLevel = Math.round(v)
                        }

                        PlasmaComponents3.Label { text: i18n("Presets") }
                        Flow {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            Repeater {
                                model: [
                                    { label: i18n("Translation only"), orig: 0,   duck: true,  lvl: 0 },
                                    { label: i18n("Dub"), orig: 100, duck: true,  lvl: 20 },
                                    { label: i18n("Interpreter"),     orig: 60,  duck: true,  lvl: 35 },
                                    { label: i18n("Both equal"),   orig: 100, duck: false, lvl: 80 }
                                ]
                                PlasmaComponents3.Button {
                                    text: modelData.label
                                    onClicked: {
                                        full.cfg.originalVolume = modelData.orig
                                        full.cfg.duckEnabled = modelData.duck
                                        full.cfg.duckLevel = modelData.lvl
                                    }
                                }
                            }
                        }

                        Kirigami.Separator { Layout.fillWidth: true }

                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                PlasmaComponents3.Label { text: i18n("Subtitle window") }
                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: i18n("Floating live subtitles above all windows, movable with the mouse")
                                    wrapMode: Text.WordWrap
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.6
                                }
                            }
                            PlasmaComponents3.Switch {
                                checked: full.cfg.overlay
                                onToggled: full.cfg.overlay = checked
                            }
                        }
                        PlasmaComponents3.CheckBox {
                            enabled: full.cfg.overlay
                            text: i18n("Also show the original text")
                            checked: full.cfg.overlayShowOriginal
                            onToggled: full.cfg.overlayShowOriginal = checked
                        }
                    }
                    Item { implicitHeight: Kirigami.Units.smallSpacing }
                }
            }

            // ════════ Sync & Erkennung ════════
            PlasmaComponents3.ScrollView {
                contentWidth: availableWidth
                // kein waagerechter Scrollbalken – senkrecht nur, wenn der Platz wirklich nicht reicht
                PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff
                ColumnLayout {
                    id: syncCol
                    width: parent.width
                    spacing: Kirigami.Units.largeSpacing

                    Item { implicitHeight: 1 }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.largeSpacing
                        Layout.rightMargin: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.largeSpacing

                        Kirigami.Heading { level: 5; text: i18n("Dub") }

                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                PlasmaComponents3.Label { text: i18n("Follow seeking & pausing") }
                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: root.mediaConnected || !root.backendOnline
                                          ? i18n("Detects seeking and pausing in YouTube, Udemy, VLC … and drops everything old immediately")
                                          : i18n("Media detection not connected yet – switch the widget off and on")
                                    wrapMode: Text.WordWrap
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.6
                                }
                            }
                            PlasmaComponents3.Switch {
                                checked: full.cfg.mediaSync
                                onToggled: full.cfg.mediaSync = checked
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                PlasmaComponents3.Label { text: i18n("Adapt tempo automatically") }
                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: i18n("If the original is spoken fast, the voice speaks faster too – without sounding higher. Sentences are never cut off.")
                                    wrapMode: Text.WordWrap
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.6
                                }
                            }
                            PlasmaComponents3.Switch {
                                checked: full.cfg.adaptiveTempo
                                onToggled: full.cfg.adaptiveTempo = checked
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                PlasmaComponents3.Label { text: i18n("Emergency jump on large backlog") }
                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: i18n("Only if even the faster tempo is not enough: jumps to the current position between two sentences")
                                    wrapMode: Text.WordWrap
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.6
                                }
                            }
                            PlasmaComponents3.Switch {
                                checked: full.cfg.syncMode
                                onToggled: full.cfg.syncMode = checked
                            }
                        }

                        SettingSlider {
                            enabled: full.cfg.syncMode
                            opacity: enabled ? 1 : 0.5
                            label: i18n("Jump only after a backlog of")
                            unit: "s"
                            from: 4; to: 20; stepSize: 1
                            resetValue: 8
                            value: full.cfg.emergencyLag
                            onMoved: v => full.cfg.emergencyLag = Math.round(v)
                        }

                        Kirigami.Separator { Layout.fillWidth: true }
                        Kirigami.Heading { level: 5; text: i18n("Recognition & translation") }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            PlasmaComponents3.Label { text: i18n("Speech recognition") }
                            PlasmaComponents3.ComboBox {
                                Layout.fillWidth: true
                                model: full.recognizerOptions
                                textRole: "text"; valueRole: "value"
                                currentIndex: full.indexOf(full.recognizerOptions, full.cfg.recognizer)
                                onActivated: idx => full.cfg.recognizer = full.recognizerOptions[idx].value
                            }

                            Item { implicitHeight: Kirigami.Units.smallSpacing }
                            PlasmaComponents3.Label { text: i18n("Responsiveness") }
                            PlasmaComponents3.ComboBox {
                                Layout.fillWidth: true
                                model: full.responsivenessOptions
                                textRole: "text"; valueRole: "value"
                                currentIndex: full.indexOf(full.responsivenessOptions, full.cfg.responsiveness)
                                onActivated: idx => full.cfg.responsiveness = full.responsivenessOptions[idx].value
                            }

                            Item { implicitHeight: Kirigami.Units.smallSpacing }
                            PlasmaComponents3.Label { text: i18n("Translator") }
                            PlasmaComponents3.ComboBox {
                                Layout.fillWidth: true
                                model: full.translatorOptions
                                textRole: "text"; valueRole: "value"
                                currentIndex: full.indexOf(full.translatorOptions, full.cfg.translator)
                                onActivated: idx => full.cfg.translator = full.translatorOptions[idx].value
                            }
                            PlasmaExtras.PasswordField {
                                Layout.fillWidth: true
                                visible: full.cfg.translator === "deepl"
                                placeholderText: i18n("DeepL API key (free at deepl.com/pro-api)")
                                text: full.cfg.deeplKey
                                onEditingFinished: full.cfg.deeplKey = text.trim()
                            }
                        }

                        SettingSlider {
                            label: i18n("Sensitivity (higher = ignores quiet noise)")
                            unit: ""
                            from: 1; to: 10; stepSize: 1
                            resetValue: 3
                            value: full.cfg.sensitivity
                            onMoved: v => full.cfg.sensitivity = Math.round(v)
                        }

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: i18n("Whisper runs privately on your computer. Switching languages briefly loads a matching model the first time.")
                            wrapMode: Text.WordWrap
                            font: Kirigami.Theme.smallFont
                            opacity: 0.6
                        }

                        PlasmaComponents3.Button {
                            icon.name: "run-install"
                            text: i18n("Run setup again")
                            onClicked: root.runSetup()
                        }
                    }
                    Item { implicitHeight: Kirigami.Units.smallSpacing }
                }
            }

            // ════════ Verlauf ════════
            ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

                    ListView {
                        id: historyView
                        clip: true
                        model: root.history.slice().reverse()
                        spacing: Kirigami.Units.smallSpacing
                        topMargin: Kirigami.Units.smallSpacing

                        delegate: ColumnLayout {
                            width: historyView.width - Kirigami.Units.largeSpacing * 2
                            x: Kirigami.Units.largeSpacing
                            spacing: 2
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: modelData.t + "  ·  " + modelData.src
                                wrapMode: Text.WordWrap
                                font: Kirigami.Theme.smallFont
                                opacity: 0.6
                            }
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: modelData.dst
                                wrapMode: Text.WordWrap
                            }
                            Kirigami.Separator { Layout.fillWidth: true; opacity: 0.5 }
                        }

                        PlasmaExtras.PlaceholderMessage {
                            anchors.centerIn: parent
                            width: parent.width - Kirigami.Units.gridUnit * 2
                            visible: historyView.count === 0
                            iconName: "view-history"
                            text: i18n("Nothing translated yet")
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                    Item { Layout.fillWidth: true }
                    PlasmaComponents3.Button {
                        icon.name: "edit-copy"
                        text: i18n("Copy all")
                        enabled: historyView.count > 0
                        onClicked: {
                            var out = []
                            for (var i = 0; i < root.history.length; ++i) {
                                var h = root.history[i]
                                out.push("[" + h.t + "] " + h.src + "\n→ " + h.dst)
                            }
                            clipHelper.text = out.join("\n\n")
                            clipHelper.selectAll()
                            clipHelper.copy()
                        }
                    }
                    PlasmaComponents3.Button {
                        icon.name: "edit-clear-history"
                        text: i18n("Clear")
                        enabled: historyView.count > 0
                        onClicked: root.clearHistory()
                    }
                }

                TextEdit { id: clipHelper; visible: false }
            }
        }
    }
}
