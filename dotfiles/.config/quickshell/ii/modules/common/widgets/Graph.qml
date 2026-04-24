import QtQuick
import qs.modules.common
import qs.modules.common.functions

/*
 * Simple one value line graph
 */
Canvas {
    id: root

    enum Alignment { Left, Right }

    required property list<real> values
    property int points: values.length
    property color color: Appearance.colors.colPrimary
    property real fillOpacity: 0.5
    property var alignment: Graph.Alignment.Left

    onValuesChanged: root.requestPaint()
    onPaint: {
        const paintWidth = Number(width)
        const paintHeight = Number(height)
        if (!Number.isFinite(paintWidth) || !Number.isFinite(paintHeight) || paintWidth <= 0 || paintHeight <= 0)
            return

        var ctx = getContext("2d")
        if (!ctx)
            return

        ctx.clearRect(0, 0, paintWidth, paintHeight)
        if (!root.values || root.values.length < 2)
            return

        var n = root.points
        if (!Number.isFinite(n) || n < 2)
            return

        var dx = paintWidth / (n - 1)
        ctx.strokeStyle = root.color
        ctx.fillStyle = ColorUtils.transparentize(root.color, 1 - root.fillOpacity)
        ctx.lineWidth = 2
        ctx.beginPath()
        for (var i = 0; i < n; ++i) {
            var valueIndex = (root.alignment === Graph.Alignment.Right) ? root.values.length - n + i : i
            if (valueIndex < 0 || valueIndex >= root.values.length) {
                continue; // No data for this point
            }
            var x = i * dx
            var norm = Math.max(0, Math.min(1, Number(root.values[valueIndex]) || 0)) // already in 0-1 range
            var y = paintHeight - norm * paintHeight
            if (valueIndex === 0) {
                ctx.moveTo(x, paintHeight)
                ctx.lineTo(x, y)
            } else {
                ctx.lineTo(x, y)
            }
        }
        ctx.stroke()
        ctx.lineTo(paintWidth, paintHeight)
        ctx.fill()
    }
}
