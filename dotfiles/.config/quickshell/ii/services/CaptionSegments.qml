pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import "CaptionSegmentUtils.js" as SegmentUtils

QtObject {
    id: root

    readonly property int maximumSegments: 6
    readonly property string surfaceColor: Appearance.colors.colLayer1Base.toString()
    readonly property string neutralColor: Appearance.colors.colOnSurface.toString()
    readonly property real minimumContrast: Appearance.highContrast ? 7 : 4.5
    readonly property var sentencePalette: Appearance.m3colors.darkmode
        ? ["#a8c7fa", "#d0bcff", "#f2b8da", "#ffd180", "#a5d6a7", "#80deea"]
        : ["#3156a6", "#6a3e99", "#8c2c69", "#875200", "#17673b", "#076678"]

    function sanitizeSegments(payload) {
        return SegmentUtils.sanitizeSegments(payload, root.maximumSegments)
    }

    function colorForId(id) {
        return SegmentUtils.colorForId(id, root.sentencePalette, root.surfaceColor, root.minimumContrast)
    }

    function markup(payload, translated = false) {
        return SegmentUtils.markup(root.sanitizeSegments(payload), translated,
            root.sentencePalette, root.surfaceColor, root.neutralColor, root.minimumContrast)
    }

    function plainText(payload, translated = false) {
        return SegmentUtils.plainText(root.sanitizeSegments(payload), translated)
    }

    function hasCompletedPairs(payload) {
        return root.sanitizeSegments(payload).some(segment => !segment.pending)
    }
}
