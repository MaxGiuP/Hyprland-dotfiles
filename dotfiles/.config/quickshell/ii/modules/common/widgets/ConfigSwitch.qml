import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root

    default property alias contentData: button.data

    property string buttonIcon
    property real iconSize: Appearance.font.pixelSize.larger
    property bool checked: false
    property bool highlightChecked: false
    property color switchActiveColor: Appearance.colors.colPrimary

    property alias text: button.text
    property alias font: button.font
    property alias pointingHandCursor: button.pointingHandCursor
    property alias buttonRadius: button.buttonRadius
    property alias buttonRadiusPressed: button.buttonRadiusPressed
    property alias rippleDuration: button.rippleDuration
    property alias rippleEnabled: button.rippleEnabled
    property alias downAction: button.downAction
    property alias releaseAction: button.releaseAction
    property alias altAction: button.altAction
    property alias middleClickAction: button.middleClickAction
    property alias colBackground: button.colBackground
    property alias colBackgroundHover: button.colBackgroundHover
    property alias colBackgroundToggled: button.colBackgroundToggled
    property alias colBackgroundToggledHover: button.colBackgroundToggledHover
    property alias colRipple: button.colRipple
    property alias colRippleToggled: button.colRippleToggled
    property alias horizontalPadding: button.horizontalPadding
    property alias verticalPadding: button.verticalPadding
    property alias leftPadding: button.leftPadding
    property alias rightPadding: button.rightPadding
    property alias topPadding: button.topPadding
    property alias bottomPadding: button.bottomPadding
    readonly property alias down: button.down

    signal clicked()

    Layout.fillWidth: true
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    RippleButton {
        id: button
        anchors.fill: parent

        enabled: root.enabled
        toggled: root.highlightChecked && root.checked
        font.pixelSize: Appearance.font.pixelSize.small

        onClicked: {
            root.checked = !root.checked;
            root.clicked();
        }

        contentItem: Item {
            implicitWidth: row.implicitWidth
            implicitHeight: row.implicitHeight

            RowLayout {
                id: row
                anchors.fill: parent
                spacing: 10

                MaterialSymbol {
                    visible: !!root.buttonIcon && !Appearance.disableVariableFonts
                    text: root.buttonIcon
                    iconSize: root.iconSize
                    color: root.highlightChecked && root.checked ? button.colForegroundToggled : Appearance.colors.colOnSecondaryContainer
                    opacity: root.enabled ? 1 : 0.4
                }

                StyledText {
                    Layout.fillWidth: true
                    useDefaultVariableAxes: false
                    text: root.text
                    font: root.font
                    color: root.highlightChecked && root.checked ? button.colForegroundToggled : Appearance.colors.colOnSecondaryContainer
                    opacity: root.enabled ? 1 : 0.4
                }

                StyledSwitch {
                    id: styledSwitch
                    visible: true
                    down: button.down
                    checked: root.checked
                    activeColor: root.switchActiveColor

                    onClicked: button.click()
                }
            }
        }
    }
}
