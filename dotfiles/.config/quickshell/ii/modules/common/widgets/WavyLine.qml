import qs.modules.common
import QtQuick

Canvas {
    id: root
    property real amplitudeMultiplier: 0.5
    property real frequency: 6
    property color color: Appearance?.colors.colPrimary ?? "#685496"
    property real lineWidth: 4
    property real fullLength: width

    onPaint: {
        const paintWidth = Number(width);
        const paintHeight = Number(height);
        const length = Number(root.fullLength);
        if (!Number.isFinite(paintWidth) || !Number.isFinite(paintHeight)
                || !Number.isFinite(length) || paintWidth <= 0 || paintHeight <= 0 || length <= 0)
            return;

        var ctx = getContext("2d");
        if (!ctx)
            return;

        ctx.clearRect(0, 0, paintWidth, paintHeight);

        var amplitude = root.lineWidth * root.amplitudeMultiplier;
        var frequency = root.frequency;
        var phase = Date.now() / 400.0;
        var centerY = paintHeight / 2;

        ctx.strokeStyle = root.color;
        ctx.lineWidth = root.lineWidth;
        ctx.lineCap = "round";
        ctx.beginPath();
        for (var x = ctx.lineWidth / 2, i = 0; x <= paintWidth - ctx.lineWidth / 2; x += 1, i++) {
            var waveY = centerY + amplitude * Math.sin(frequency * 2 * Math.PI * x / length + phase);
            if (i === 0)
                ctx.moveTo(x, waveY);
            else
                ctx.lineTo(x, waveY);
        }
        ctx.stroke();
    }
}
