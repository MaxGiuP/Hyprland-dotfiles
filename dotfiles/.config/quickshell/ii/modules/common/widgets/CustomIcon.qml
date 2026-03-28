import QtQuick
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

Item {
    id: root
    
    property bool colorize: false
    property color color
    property string source: ""
    property string iconFolder: Qt.resolvedUrl(Quickshell.shellPath("assets/icons"))  // The folder to check first
    property string resolvedSource: {
        const requestedSource = String(root.source ?? "").trim();
        if (requestedSource.length === 0)
            return "";
        if (requestedSource.includes("://") || requestedSource.startsWith("/") || requestedSource.startsWith("qrc:/") || requestedSource.startsWith("qs:@/"))
            return requestedSource;

        const fileName = requestedSource.endsWith(".svg") ? requestedSource : `${requestedSource}.svg`;
        return `${iconFolder}/${fileName}`;
    }
    width: 30
    height: 30
    
    IconImage {
        id: iconImage
        anchors.fill: parent
        source: root.resolvedSource
        implicitSize: root.height
    }

    Loader {
        active: root.colorize
        anchors.fill: iconImage
        sourceComponent: ColorOverlay {
            source: iconImage
            color: root.color
        }
    }
}
