import QtQuick
import "shapes/morph.js" as Morph

Canvas {
    id: root
    property color color: "#685496"
    property var roundedPolygon: null
    property bool polygonIsNormalized: true
    renderTarget: Canvas.Image
    renderStrategy: Canvas.Cooperative
    antialiasing: true

    // Internals: size
    readonly property bool hasValidPolygon: !!roundedPolygon && typeof roundedPolygon.calculateBounds === "function"
    property var bounds: hasValidPolygon ? roundedPolygon.calculateBounds() : [0, 0, 0, 0]
    implicitWidth: hasValidPolygon ? Math.max(0, bounds[2] - bounds[0]) : 0
    implicitHeight: hasValidPolygon ? Math.max(0, bounds[3] - bounds[1]) : 0

    // Internals: anim
    property var prevRoundedPolygon: null
    property double progress: 1
    property var morph: null
    property Animation animation: NumberAnimation {
        duration: 350
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.42, 1.67, 0.21, 0.90, 1, 1] // Material 3 Expressive fast spatial (https://m3.material.io/styles/motion/overview/specs)
    }

    function rebuildMorph() {
        if (!root.hasValidPolygon) {
            delete root.morph
            root.morph = null
            root.prevRoundedPolygon = null
            root.progress = 1
            root.requestPaint()
            return
        }

        delete root.morph
        root.morph = new Morph.Morph(root.prevRoundedPolygon ?? root.roundedPolygon, root.roundedPolygon)
        morphBehavior.enabled = false
        root.progress = 0
        morphBehavior.enabled = true
        root.progress = 1
        root.prevRoundedPolygon = root.roundedPolygon
        root.requestPaint()
    }
    
    onRoundedPolygonChanged: {
        root.rebuildMorph()
    }
    Component.onCompleted: root.rebuildMorph()

    Behavior on progress {
        id: morphBehavior
        animation: root.animation
    }

    onProgressChanged: requestPaint()
    onColorChanged: requestPaint()
    onPaint: {
        const paintWidth = Math.floor(Number(root.width))
        const paintHeight = Math.floor(Number(root.height))
        if (!Number.isFinite(paintWidth) || !Number.isFinite(paintHeight) || paintWidth <= 0 || paintHeight <= 0)
            return

        if (!root.hasValidPolygon || !root.morph)
            return

        var ctx = getContext("2d")
        if (!ctx)
            return

        ctx.fillStyle = root.color
        ctx.clearRect(0, 0, paintWidth, paintHeight)
        const cubics = root.morph.asCubics(root.progress)
        if (cubics.length === 0)
            return

        const size = Math.min(paintWidth, paintHeight)
        if (!Number.isFinite(size) || size <= 0)
            return

        const offsetX = paintWidth / 2 - size / 2
        const offsetY = paintHeight / 2 - size / 2

        ctx.save()
        ctx.translate(offsetX, offsetY)
        if (root.polygonIsNormalized)
            ctx.scale(size, size)

        ctx.beginPath()
        ctx.moveTo(cubics[0].anchor0X, cubics[0].anchor0Y)
        for (const cubic of cubics) {
            ctx.bezierCurveTo(
                cubic.control0X, cubic.control0Y,
                cubic.control1X, cubic.control1Y,
                cubic.anchor1X, cubic.anchor1Y
            )
        }
        ctx.closePath()
        ctx.fill()
        ctx.restore()
    }
}
