pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
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
        id: seg

        required property int segValue
        required property int segMax
        required property string segLabel

        signal segChanged(int newValue)

        implicitWidth: 58
        implicitHeight: segLayout.implicitHeight

        function increment() {
            segChanged(segValue >= segMax ? 0 : segValue + 1);
        }
        function decrement() {
            segChanged(segValue <= 0 ? segMax : segValue - 1);
        }

        ColumnLayout {
            id: segLayout
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: "▲"
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: seg.segValue.toString().padStart(2, "0")
                font.pixelSize: 26
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: "▼"
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: seg.segLabel
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            property real pressY: 0
            property int valueAtPress: 0
            property bool didDrag: false

            onPressed: event => {
                pressY = event.y;
                valueAtPress = seg.segValue;
                didDrag = false;
            }
            onPositionChanged: event => {
                if (!pressed) return;
                const delta = Math.floor((pressY - event.y) / 7);
                if (delta !== 0) didDrag = true;
                const range = seg.segMax + 1;
                seg.segChanged(((valueAtPress + delta) % range + range) % range);
            }
            onClicked: event => {
                if (didDrag) return;
                if (event.y < seg.height * 0.4)
                    seg.increment();
                else if (event.y > seg.height * 0.6)
                    seg.decrement();
            }
            onWheel: event => {
                if (event.angleDelta.y > 0) seg.increment();
                else seg.decrement();
                event.accepted = true;
            }
        }
    }

    RowLayout {
        id: timeRow
        anchors.centerIn: parent
        spacing: 0

        TimeSegment {
            segValue: root.hourValue
            segMax: 23
            segLabel: Translation.tr("or")
            onSegChanged: v => {
                root.hourValue = v;
                root.valuesChanged(root.hourValue, root.minuteValue, root.secondValue);
            }
        }

        StyledText {
            text: ":"
            font.pixelSize: 26
            Layout.alignment: Qt.AlignVCenter
            Layout.bottomMargin: 22
            leftPadding: 2
            rightPadding: 2
            color: Appearance.colors.colSubtext
        }

        TimeSegment {
            segValue: root.minuteValue
            segMax: 59
            segLabel: "min"
            onSegChanged: v => {
                root.minuteValue = v;
                root.valuesChanged(root.hourValue, root.minuteValue, root.secondValue);
            }
        }

        StyledText {
            text: ":"
            font.pixelSize: 26
            Layout.alignment: Qt.AlignVCenter
            Layout.bottomMargin: 22
            leftPadding: 2
            rightPadding: 2
            color: Appearance.colors.colSubtext
        }

        TimeSegment {
            segValue: root.secondValue
            segMax: 59
            segLabel: "sec"
            onSegChanged: v => {
                root.secondValue = v;
                root.valuesChanged(root.hourValue, root.minuteValue, root.secondValue);
            }
        }
    }
}
