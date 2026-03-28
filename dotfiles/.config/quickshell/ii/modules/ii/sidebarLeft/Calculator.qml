import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

FocusScope {
    id: root
    focus: true
    activeFocusOnTab: true

    property string expression: ""
    property string result: "0"
    property var history: []
    property var buttonModel: [
        {"label": "C"},
        {"label": "("},
        {"label": ")"},
        {"label": "%"},
        {"label": "⌫"},

        {"label": "sin("},
        {"label": "cos("},
        {"label": "tan("},
        {"label": "log("},
        {"label": "ln("},

        {"label": "7"},
        {"label": "8"},
        {"label": "9"},
        {"label": "÷"},
        {"label": "√("},

        {"label": "4"},
        {"label": "5"},
        {"label": "6"},
        {"label": "×"},
        {"label": "^"},

        {"label": "1"},
        {"label": "2"},
        {"label": "3"},
        {"label": "-"},
        {"label": "π"},

        {"label": "0", "columnSpan": 2},
        {"label": "."},
        {"label": "+"},
        {"label": "="}
    ]

    function sanitize(expr) {
        return (expr ?? "")
            .replace(/π/g, "pi")
            .replace(/√\(/g, "sqrt(")
            .replace(/÷/g, "/")
            .replace(/×/g, "*")
            .replace(/\^/g, "**");
    }

    function evalExpr(expr) {
        const trimmed = sanitize(expr).trim();
        if (trimmed.length === 0) return "0";
        if (!/^[0-9+\-*/().,%\s^pieasqrtnlogcotan]+$/i.test(trimmed)) return Translation.tr("Error");
        try {
            const scope = {
                pi: Math.PI,
                e: Math.E,
                sin: Math.sin,
                cos: Math.cos,
                tan: Math.tan,
                log: Math.log10,
                ln: Math.log,
                sqrt: Math.sqrt,
                abs: Math.abs,
            };
            const fn = Function("scope", `with (scope) { return (${trimmed.replace(/%/g, "/100")}); }`);
            const value = fn(scope);
            if (!isFinite(value)) return Translation.tr("Error");
            return `${value}`;
        } catch (e) {
            return Translation.tr("Error");
        }
    }

    function append(token) {
        root.expression += token;
        root.result = evalExpr(root.expression);
    }

    function clearAll() {
        root.expression = "";
        root.result = "0";
    }

    function backspace() {
        if (root.expression.length === 0) return;
        root.expression = root.expression.slice(0, -1);
        root.result = evalExpr(root.expression);
    }

    function evaluate() {
        const out = evalExpr(root.expression);
        root.history = [{"expr": root.expression, "out": out}, ...root.history].slice(0, 12);
        root.expression = out === Translation.tr("Error") ? "" : out;
        root.result = out;
    }

    function buttonBackground(label) {
        if (label === "=") return Appearance.colors.colPrimary;
        if (["+", "-", "×", "÷", "^"].indexOf(label) !== -1) return Appearance.colors.colSecondaryContainer;
        if (["sin(", "cos(", "tan(", "log(", "ln(", "π", "e", "√(", "%"].indexOf(label) !== -1) return Appearance.colors.colTertiaryContainer;
        if (["C", "⌫", "(", ")"].indexOf(label) !== -1) return Appearance.colors.colLayer3;
        return Appearance.colors.colLayer2;
    }

    function buttonForeground(label) {
        if (label === "=") return Appearance.colors.colOnPrimary;
        if (["+", "-", "×", "÷", "^"].indexOf(label) !== -1) return Appearance.colors.colOnSecondaryContainer;
        if (["sin(", "cos(", "tan(", "log(", "ln(", "π", "e", "√(", "%"].indexOf(label) !== -1) return Appearance.colors.colOnTertiaryContainer;
        return Appearance.colors.colOnLayer2;
    }

    Keys.onPressed: event => {
        const key = event.text;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.evaluate();
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace) {
            root.backspace();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            root.clearAll();
            event.accepted = true;
        } else if (key && /^[0-9+\-*/().%^]$/.test(key)) {
            root.append(key === "*" ? "×" : key === "/" ? "÷" : key);
            event.accepted = true;
        }
    }

    Component.onCompleted: root.forceActiveFocus()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 124
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            border.width: 1
            border.color: Appearance.colors.colLayer3

            MouseArea {
                anchors.fill: parent
                onClicked: root.forceActiveFocus()
            }

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                implicitHeight: 42
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer3

                StyledText {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    text: Translation.tr("Calculator")
                    color: Appearance.colors.colOnLayer3
                    font.pixelSize: Appearance.font.pixelSize.normal
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                anchors.topMargin: 52
                spacing: 4

                StyledText {
                    Layout.fillWidth: true
                    text: root.expression.length > 0 ? root.expression : "0"
                    horizontalAlignment: Text.AlignRight
                    wrapMode: Text.WrapAnywhere
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.huge
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.result
                    horizontalAlignment: Text.AlignRight
                    wrapMode: Text.WrapAnywhere
                    color: Appearance.colors.colOnLayer2
                    font.pixelSize: Appearance.font.pixelSize.massive
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            color: "transparent"
            implicitHeight: calcGrid.implicitHeight

            GridLayout {
                id: calcGrid
                property real keySize: Math.max(44, Math.floor((parent.width - (columns - 1) * columnSpacing) / columns))
                anchors.left: parent.left
                anchors.right: parent.right
                columns: 5
                rowSpacing: 8
                columnSpacing: 8

                Repeater {
                    model: root.buttonModel

                    delegate: RippleButton {
                        required property var modelData
                        readonly property string label: modelData.label
                        readonly property int span: modelData.columnSpan || 1
                        Layout.columnSpan: span
                        Layout.preferredWidth: calcGrid.keySize * span + calcGrid.columnSpacing * (span - 1)
                        Layout.preferredHeight: calcGrid.keySize
                        buttonRadius: span > 1 ? Appearance.rounding.full : calcGrid.keySize / 2
                        colBackground: root.buttonBackground(label)
                        colBackgroundHover: Qt.tint(root.buttonBackground(label), "#18ffffff")

                        contentItem: StyledText {
                            anchors.centerIn: parent
                            text: label
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.pixelSize: label.length > 2 ? Appearance.font.pixelSize.large : Appearance.font.pixelSize.huge
                            font.weight: label === "=" ? Font.DemiBold : Font.Medium
                            color: root.buttonForeground(label)
                        }

                        onClicked: {
                            if (label === "C") root.clearAll();
                            else if (label === "⌫") root.backspace();
                            else if (label === "=") root.evaluate();
                            else root.append(label);
                            root.forceActiveFocus();
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            border.width: 1
            border.color: Appearance.colors.colLayer3
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        text: Translation.tr("Recent")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    StyledText {
                        visible: root.history.length > 0
                        text: Translation.tr("Tap to restore")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }

                StyledFlickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: historyColumn.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: historyColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: 6

                        Repeater {
                            model: root.history

                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 52
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer3

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 10

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.expr
                                            color: Appearance.colors.colSubtext
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.small
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.out
                                            color: Appearance.colors.colOnLayer3
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                        }
                                    }

                                    MaterialSymbol {
                                        text: "north_west"
                                        iconSize: 18
                                        color: Appearance.colors.colSubtext
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        root.expression = modelData.expr;
                                        root.result = modelData.out;
                                        root.forceActiveFocus();
                                    }
                                }
                            }
                        }

                        StyledText {
                            visible: root.history.length === 0
                            Layout.fillWidth: true
                            text: Translation.tr("No calculations yet.")
                            horizontalAlignment: Text.AlignHCenter
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }
            }
        }
    }
}
