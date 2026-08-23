import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property string query: ""
    signal queryEdited(string value)

    Layout.preferredWidth: Math.max(180, Math.min(280, (parent?.width ?? 700) * 0.32))
    Layout.minimumWidth: 180
    Layout.maximumWidth: 280
    Layout.preferredHeight: 36
    implicitHeight: 36

    function clearQuery() {
        searchField.clear()
        root.queryEdited("")
        searchField.forceActiveFocus()
    }

    ToolbarTextField {
        id: searchField
        anchors.fill: parent
        leftPadding: 38
        rightPadding: clearButton.visible ? 38 : 12
        placeholderText: Translation.tr("Search settings")
        selectByMouse: true

        onTextEdited: root.queryEdited(text)
        Keys.onEscapePressed: event => {
            root.clearQuery()
            searchField.focus = false
            event.accepted = true
        }

        Binding {
            target: searchField
            property: "text"
            value: root.query
            when: !searchField.activeFocus
            restoreMode: Binding.RestoreNone
        }
    }

    MaterialSymbol {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: "search"
        iconSize: 18
        color: searchField.activeFocus ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
    }

    IconToolbarButton {
        id: clearButton
        visible: searchField.text.length > 0
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: 28
        height: 28
        text: "close"
        onClicked: root.clearQuery()

        StyledToolTip {
            text: Translation.tr("Clear search")
        }
    }
}
