/*
 * SPDX-FileCopyrightText: 2026 SeaQ
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: s
    property string label
    property string unit: "%"
    property bool signedValue: false
    property real from: 0
    property real to: 100
    property real stepSize: 1
    property real value: 0
    property real resetValue: NaN
    signal moved(real v)

    spacing: 0
    Layout.fillWidth: true

    RowLayout {
        Layout.fillWidth: true
        PlasmaComponents3.Label {
            text: s.label
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
        PlasmaComponents3.ToolButton {
            visible: !isNaN(s.resetValue) && s.value !== s.resetValue
            icon.name: "edit-undo"
            display: PlasmaComponents3.AbstractButton.IconOnly
            text: i18n("Reset")
            implicitHeight: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
            implicitWidth: implicitHeight
            onClicked: s.moved(s.resetValue)
            PlasmaComponents3.ToolTip.text: text
            PlasmaComponents3.ToolTip.visible: hovered
        }
        PlasmaComponents3.Label {
            text: (s.signedValue && s.value > 0 ? "+" : "") + Math.round(s.value) + " " + s.unit
            opacity: 0.7
            font.features: ({ "tnum": 1 })
        }
    }
    PlasmaComponents3.Slider {
        Layout.fillWidth: true
        from: s.from
        to: s.to
        stepSize: s.stepSize
        value: s.value
        onMoved: s.moved(value)
        id: sl

        // Schiene + gefüllter Teil in der Akzentfarbe des Farbschemas
        background: Item {
            x: sl.leftPadding
            y: sl.topPadding + sl.availableHeight / 2 - height / 2
            width: sl.availableWidth
            height: Math.round(Kirigami.Units.smallSpacing * 1.5)
            implicitWidth: Kirigami.Units.gridUnit * 10
            implicitHeight: height

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: root.alpha(root.cText, 0.18)
            }
            Rectangle {
                width: sl.visualPosition * parent.width
                height: parent.height
                radius: height / 2
                color: root.cAccent
            }
        }

        handle: Rectangle {
            readonly property real size: Math.round(Kirigami.Units.gridUnit * 0.95)
            x: sl.leftPadding + sl.visualPosition * (sl.availableWidth - width)
            y: sl.topPadding + sl.availableHeight / 2 - height / 2
            implicitWidth: size
            implicitHeight: size
            radius: size / 2
            color: sl.pressed ? Qt.lighter(root.cAccent, 1.15) : (sl.hovered ? root.cAccent : root.cButton)
            border.width: 2
            border.color: root.cAccent
            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
        }
    }
}
