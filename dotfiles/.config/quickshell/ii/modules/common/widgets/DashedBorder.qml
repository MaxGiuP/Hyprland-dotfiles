import QtQuick
import qs.modules.common
import qs.modules.common.functions

Canvas {
    id: root
    property color color: "#ffffff"
    property int dashLength: 6
    property int gapLength: 4
    property int borderWidth: 1

    onDashLengthChanged: requestPaint()
    onGapLengthChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const paintWidth = Number(width);
        const paintHeight = Number(height);
        if (!Number.isFinite(paintWidth) || !Number.isFinite(paintHeight) || paintWidth <= 0 || paintHeight <= 0)
            return;

        var ctx = getContext("2d");
        if (!ctx)
            return;

        ctx.clearRect(0, 0, paintWidth, paintHeight);
        ctx.save();
        ctx.strokeStyle = root.color;
        ctx.lineWidth = root.borderWidth;
        if (root.gapLength > 0) {
            ctx.setLineDash([root.dashLength, root.gapLength]); // Set dash pattern
        }
        ctx.strokeRect(root.borderWidth / 2, root.borderWidth / 2, paintWidth - root.borderWidth, paintHeight - root.borderWidth); // Draw it
        ctx.restore();
    }
}
