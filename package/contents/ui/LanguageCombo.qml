/*
 * SPDX-FileCopyrightText: 2026 SeaQ
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// Sprachauswahl mit Stern: markierte Sprachen stehen ganz oben in der Liste
PlasmaComponents3.ComboBox {
    id: combo
    property string current: ""
    signal picked(string code)

    textRole: "text"
    valueRole: "value"
    displayText: {
        for (var i = 0; i < model.length; ++i)
            if (model[i].value === current) return model[i].text
        return current
    }
    currentIndex: {
        for (var i = 0; i < model.length; ++i)
            if (model[i].value === current) return i
        return -1
    }
    onActivated: idx => picked(model[idx].value)

    delegate: PlasmaComponents3.ItemDelegate {
        id: item
        width: ListView.view ? ListView.view.width : combo.width
        highlighted: combo.highlightedIndex === index

        contentItem: RowLayout {
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: modelData.text
                elide: Text.ElideRight
                font.weight: modelData.value === combo.current ? Font.DemiBold : Font.Normal
                color: item.highlighted ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
            }
            PlasmaComponents3.ToolButton {
                visible: modelData.value !== "auto"
                icon.name: modelData.fav ? "rating" : "rating-unrated"
                opacity: modelData.fav || item.hovered ? 1.0 : 0.45
                display: PlasmaComponents3.AbstractButton.IconOnly
                text: modelData.fav ? i18n("Unpin") : i18n("Pin to top")
                implicitWidth: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                implicitHeight: implicitWidth
                onClicked: root.toggleFavorite(modelData.value)
                PlasmaComponents3.ToolTip.text: text
                PlasmaComponents3.ToolTip.visible: hovered
            }
        }

        // Trennlinie zwischen angehefteten und übrigen Sprachen
        Kirigami.Separator {
            visible: modelData.lastFav === true
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
        }
    }
}
