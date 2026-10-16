/*
 * SPDX-FileCopyrightText: 2026 SeaQ
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami

// Schwebende Untertitel in den Farben des System-Farbschemas (deckend, kein Blur) –
// mit der Maus verschiebbar
Window {
    id: win
    property string translatedText: ""
    property string originalText: ""
    property bool placed: false


    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool | Qt.WindowDoesNotAcceptFocus
    color: "transparent"
    title: i18n("AlloraVoice subtitles")
    width: Math.min(Screen.width * 0.6, Kirigami.Units.gridUnit * 46)
    height: col.implicitHeight + Kirigami.Units.largeSpacing * 2

    onVisibleChanged: {
        if (visible && !placed) {
            x = Screen.virtualX + (Screen.width - width) / 2
            y = Screen.virtualY + Screen.height - height - Kirigami.Units.gridUnit * 5
            placed = true
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.cornerRadius * 2
        color: root.cWindow
        border.width: 1
        border.color: root.alpha(root.cText, 0.18)

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.SizeAllCursor
            onPressed: win.startSystemMove()
        }

        Column {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Kirigami.Units.largeSpacing * 1.5
            spacing: Kirigami.Units.smallSpacing

            Text {
                width: parent.width
                visible: win.originalText !== ""
                text: win.originalText
                color: root.cWindowText
                opacity: 0.65
                font.family: Kirigami.Theme.defaultFont.family
                font.pointSize: Kirigami.Theme.defaultFont.pointSize
                font.italic: true
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: win.translatedText
                color: root.cWindowText
                font.family: Kirigami.Theme.defaultFont.family
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.6
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                maximumLineCount: 3
                elide: Text.ElideRight
            }
        }
    }
}
