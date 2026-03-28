import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    default property alias contentData: button.data

    property string nerdIcon
    property string materialIcon
    property bool materialIconFill: true
    property string mainText: "Button text"
    property bool toggled: false
    property Component mainContentComponent: defaultMainContentComponent
    readonly property bool useCustomContent: root.mainContentComponent !== defaultMainContentComponent

    Component {
        id: defaultMainContentComponent

        StyledText {
            visible: text !== ""
            useDefaultVariableAxes: false
            text: root.mainText
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSecondaryContainer
        }
    }

    property alias font: button.font
    property alias buttonText: button.buttonText
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

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    RippleButton {
        id: button
        anchors.fill: parent

        toggled: root.toggled
        enabled: root.enabled
        buttonRadius: Appearance.rounding.small
        colBackground: Appearance.colors.colLayer2
        implicitHeight: 35
        horizontalPadding: 10

        onClicked: root.clicked()

        contentItem: Item {
            implicitWidth: row.implicitWidth
            implicitHeight: row.implicitHeight

            RowLayout {
                id: row
                anchors.fill: parent
                spacing: 10

                Item {
                    visible: !!root.materialIcon || !!root.nerdIcon
                    Layout.fillWidth: false
                    implicitWidth: Math.max(
                        materialIcon.implicitWidth,
                        nerdIconLabel.implicitWidth
                    )
                    implicitHeight: Math.max(
                        materialIcon.implicitHeight,
                        nerdIconLabel.implicitHeight
                    )

                    MaterialSymbol {
                        id: materialIcon
                        anchors.centerIn: parent
                        visible: !root.nerdIcon && !!root.materialIcon
                        text: root.materialIcon
                        iconSize: Appearance.font.pixelSize.larger
                        color: root.toggled ? button.colForegroundToggled : Appearance.colors.colOnSecondaryContainer
                        fill: root.materialIconFill ? 1 : 0
                    }

                    StyledText {
                        id: nerdIconLabel
                        anchors.centerIn: parent
                        visible: !!root.nerdIcon
                        useDefaultVariableAxes: false
                        text: root.nerdIcon
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.family: Appearance.font.family.iconNerd
                        color: root.toggled ? button.colForegroundToggled : Appearance.colors.colOnSecondaryContainer
                    }
                }

                StyledText {
                    visible: !root.useCustomContent || Appearance.disableVariableFonts
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    useDefaultVariableAxes: false
                    text: root.mainText
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.toggled ? button.colForegroundToggled : Appearance.colors.colOnSecondaryContainer
                }

                Loader {
                    visible: root.useCustomContent && !Appearance.disableVariableFonts
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    sourceComponent: root.mainContentComponent
                }
            }
        }
    }
}
