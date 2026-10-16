/*
 * SPDX-FileCopyrightText: 2026 SeaQ
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

MouseArea {
    id: compact
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    activeFocusOnTab: true

    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton)
            root.setActive(!(root.running || root.starting))   // Mittelklick = schnell an/aus
        else
            root.expanded = !root.expanded
    }

    // dezenter Leuchtring, wenn aktiv (Hervorhebungsfarbe des Themes)
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) * 0.92
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: root.cAccent
        opacity: root.running ? 0.25 + root.level * 0.75 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    // immer das Kopfhörer-Symbol – ausgeschaltet etwas gedämpft
    Kirigami.Icon {
        id: icon
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) * 0.72
        height: width
        source: "audio-headset"
        active: compact.containsMouse
        opacity: (root.running || root.starting || compact.containsMouse) ? 1.0 : 0.7
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
    }

    // Statuspunkt unten rechts
    Rectangle {
        visible: root.running || root.busy || root.stateName === "error"
        width: Math.max(6, icon.width * 0.3)
        height: width
        radius: width / 2
        anchors.right: icon.right
        anchors.bottom: icon.bottom
        color: root.stateColor
        border.width: 1
        border.color: Kirigami.Theme.backgroundColor

        SequentialAnimation on opacity {
            running: root.busy || root.stateName === "speaking"
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 0.3; duration: 500 }
            NumberAnimation { to: 1.0; duration: 500 }
        }
    }
}
