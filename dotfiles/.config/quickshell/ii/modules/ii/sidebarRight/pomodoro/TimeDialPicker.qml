pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    property int hourValue: 0
    property int minuteValue: 0
    property int secondValue: 0

    signal valuesChanged(int hourValue, int minuteValue, int secondValue)

    implicitWidth: timeRow.implicitWidth
    implicitHeight: timeRow.implicitHeight

    component TimeSegment: Item {
        id: segment

        required property int segmentValue
        required property int maximumValue
        required property string label

        signal segmentChanged(int newValue)

        implicitWidth: 70
        implicitHeight: segmentLayout.implicitHeight

        function setValue(value) {
            const range = segment.maximumValue + 1;
            segment.segmentChanged(((value % range) + range) % range);
        }

        function increment() {
            segment.setValue(segment.segmentValue + 1);
        }

        function decrement() {
            segment.setValue(segment.segmentValue - 1);
        }

        function commitInput() {
            const parsed = parseInt(valueInput.text);
            if (isNaN(parsed)) {
                valueInput.text = segment.segmentValue.toString().padStart(2, "0");
                return;
            }
            const nextValue = Math.max(0, Math.min(segment.maximumValue, parsed));
            segment.segmentChanged(nextValue);
            valueInput.text = nextValue.toString().padStart(2, "0");
        }

        ColumnLayout {
            id: segmentLayout
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 3

            RippleButton {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 30
                implicitHeight: 24
                buttonRadius: Appearance.rounding.small
                onClicked: segment.increment()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "keyboard_arrow_up"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer2
                }
            }

            TextField {
                id: valueInput
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 58
                implicitHeight: 42
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                leftPadding: 4
                rightPadding: 4
                selectByMouse: true
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 0; top: segment.maximumValue }
                color: Appearance.colors.colOnLayer2
                selectionColor: Appearance.colors.colPrimaryContainer
                selectedTextColor: Appearance.colors.colOnPrimaryContainer
                font.family: Appearance.font.family.numbers
                font.pixelSize: 24
                text: segment.segmentValue.toString().padStart(2, "0")

                background: Rectangle {
                    radius: Appearance.rounding.small
                    color: valueInput.activeFocus ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
                    border.width: valueInput.activeFocus ? 2 : 1
                    border.color: valueInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                }

                onActiveFocusChanged: {
                    if (activeFocus)
                        selectAll();
                    else
                        segment.commitInput();
                }
                onAccepted: {
                    segment.commitInput();
                    nextItemInFocusChain(true).forceActiveFocus();
                }
                Keys.onUpPressed: event => {
                    segment.increment();
                    event.accepted = true;
                }
                Keys.onDownPressed: event => {
                    segment.decrement();
                    event.accepted = true;
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: event => {
                        if (event.angleDelta.y > 0)
                            segment.increment();
                        else if (event.angleDelta.y < 0)
                            segment.decrement();
                        event.accepted = true;
                    }
                }
            }

            RippleButton {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 30
                implicitHeight: 24
                buttonRadius: Appearance.rounding.small
                onClicked: segment.decrement()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "keyboard_arrow_down"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer2
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: segment.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    RowLayout {
        id: timeRow
        anchors.centerIn: parent
        spacing: 4

        TimeSegment {
            segmentValue: root.hourValue
            maximumValue: 23
            label: Translation.tr("hr")
            onSegmentChanged: value => {
                root.hourValue = value;
                root.valuesChanged(root.hourValue, root.minuteValue, root.secondValue);
            }
        }

        StyledText {
            text: ":"
            font.pixelSize: 26
            Layout.alignment: Qt.AlignVCenter
            Layout.bottomMargin: 24
            color: Appearance.colors.colSubtext
        }

        TimeSegment {
            segmentValue: root.minuteValue
            maximumValue: 59
            label: Translation.tr("min")
            onSegmentChanged: value => {
                root.minuteValue = value;
                root.valuesChanged(root.hourValue, root.minuteValue, root.secondValue);
            }
        }

        StyledText {
            text: ":"
            font.pixelSize: 26
            Layout.alignment: Qt.AlignVCenter
            Layout.bottomMargin: 24
            color: Appearance.colors.colSubtext
        }

        TimeSegment {
            segmentValue: root.secondValue
            maximumValue: 59
            label: Translation.tr("sec")
            onSegmentChanged: value => {
                root.secondValue = value;
                root.valuesChanged(root.hourValue, root.minuteValue, root.secondValue);
            }
        }
    }
}
