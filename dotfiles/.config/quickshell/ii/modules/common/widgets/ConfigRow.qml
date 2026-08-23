import QtQuick
import QtQuick.Layouts

GridLayout {
    id: root
    property bool uniform: false
    property bool adaptive: true
    property int preferredColumns: 2
    property real collapseWidth: 560

    Layout.fillWidth: true
    columns: root.adaptive && width < root.collapseWidth ? 1 : root.preferredColumns
    columnSpacing: 8
    rowSpacing: 8
    uniformCellWidths: uniform
}
