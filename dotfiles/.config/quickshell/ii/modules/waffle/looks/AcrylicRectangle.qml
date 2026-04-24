import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks

Rectangle {
    id: root

    property bool shiny: true // Top border
    property color borderColor: ColorUtils.transparentize(Looks.colors.bg1Hover, 0.7)
    property color internalBorderColor: ColorUtils.transparentize(borderColor, shiny ? 0.0 : 1)
    color: Looks.colors.bg1Hover
    radius: Looks.radius.medium
    Behavior on color {
        animation: Looks.transition.color.createObject(this)
    }
    Behavior on internalBorderColor {
        animation: Looks.transition.color.createObject(this)
    }
    onInternalBorderColorChanged: {
        borderCanvas.requestPaint();
    }
    
    // 1px border at the top or bottom
    Canvas {
        id: borderCanvas
        anchors.fill: parent
        // For dark mode we have a shiny top border, and for light mode we have sort of a shadow
        rotation: Looks.dark ? 0 : 180
        onPaint: {
            const paintWidth = Number(width);
            const paintHeight = Number(height);
            if (!Number.isFinite(paintWidth) || !Number.isFinite(paintHeight) || paintWidth <= 0 || paintHeight <= 0)
                return;

            var ctx = getContext("2d");
            if (!ctx)
                return;

            ctx.clearRect(0, 0, paintWidth, paintHeight);

            var borderColor = root.internalBorderColor;

            var r = root.radius;
            var fadeLength = Math.max(1, r);
            var fadeLengthPercent = fadeLength / paintWidth;

            // Compute normalized stops
            var leftFadeStop = fadeLengthPercent;
            var rightFadeStop = 1 - fadeLengthPercent;

            var grad = ctx.createLinearGradient(0, 0, paintWidth, 0);
            grad.addColorStop(0, Qt.rgba(borderColor.r, borderColor.g, borderColor.b, 0));
            grad.addColorStop(leftFadeStop, borderColor);
            grad.addColorStop(rightFadeStop, borderColor);
            grad.addColorStop(1, Qt.rgba(borderColor.r, borderColor.g, borderColor.b, 0));

            ctx.strokeStyle = grad;
            ctx.lineWidth = 1;

            ctx.beginPath();
            ctx.moveTo(r, 0.5);
            ctx.lineTo(paintWidth - r, 0.5);
            // Top-right curve
            ctx.arcTo(paintWidth, 0.5, paintWidth, r + 0.5, r);
            // Top-left curve
            ctx.moveTo(paintWidth - r, 0.5);
            ctx.arcTo(0, 0.5, 0, r + 0.5, r);
            ctx.stroke();
        }
    }
}
