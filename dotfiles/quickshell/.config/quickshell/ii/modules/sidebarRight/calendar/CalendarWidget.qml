import qs.modules.common
import qs
import qs.modules.common.widgets
import "./calendar_layout.js" as CalendarLayout
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    anchors.topMargin: 10
    property int monthShift: 0
    property var viewingDate: CalendarLayout.getDateInXMonthsTime(monthShift)
    property var calendarLayout: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0)
    width: calendarColumn.width
    implicitHeight: calendarColumn.height + 10 * 2

    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)
            && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown) monthShift++;
            else if (event.key === Qt.Key_PageUp) monthShift--;
            event.accepted = true;
        }
    }

    ColumnLayout {
        id: calendarColumn
        anchors.centerIn: parent
        spacing: 5

        // Calendar header
        RowLayout {
            Layout.fillWidth: true
            
            spacing: 5
            CalendarHeaderButton {
                clip: true
                buttonText: {
                    const m = viewingDate.getMonth();
                    const y = viewingDate.getFullYear();
                    const monthKeys = [
                        "January","February","March","April","May","June",
                        "July","August","September","October","November","December"
                    ];
                    let monthName = Translation.tr(monthKeys[m]);
                    if (monthName && monthName.length)
                        monthName = monthName.charAt(0).toLocaleUpperCase() + monthName.slice(1);
                    const label = `${monthName} ${y}`;
                    return `${monthShift !== 0 ? "• " : ""}${label}`;
                }
                tooltipText: (monthShift === 0) ? "" : Translation.tr("Jump to current month")
                onClicked: monthShift = 0
            }
            Item { Layout.fillWidth: true }
            CalendarHeaderButton {
                forceCircle: true
                onClicked: monthShift--
                contentItem: MaterialSymbol {
                    text: "chevron_left"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton      // <- doesn’t intercept clicks
                    cursorShape: Qt.PointingHandCursor
                }
            }
            
            CalendarHeaderButton {
                forceCircle: true
                onClicked: monthShift++
                contentItem: MaterialSymbol {
                    text: "chevron_right"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        // Week days row
        RowLayout {
            id: weekDaysRow
            Layout.alignment: Qt.AlignHCenter
            spacing: 5
            Repeater {
                model: CalendarLayout.weekDays
                delegate: CalendarDayButton {
                    day: Translation.tr(modelData.day)
                    isToday: modelData.today
                    bold: true
                    enabled: false
                }
            }
        }

        // Real week rows
        Repeater {
            id: calendarRows
            model: 6
            delegate: RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 5
                Repeater {
                    model: Array(7).fill(modelData)
                    delegate: CalendarDayButton {
                        day: calendarLayout[modelData][index].day
                        isToday: calendarLayout[modelData][index].today
                    }
                }
            }
        }
    }

    // Smooth scroll without blocking clicks
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            if (event.angleDelta.y > 0) monthShift--;
            else if (event.angleDelta.y < 0) monthShift++;
            event.accepted = true;
        }
    }

    // Right-click launcher overlay that doesn't eat left clicks
    MouseArea {
        anchors.fill: parent
        z: 9999
        acceptedButtons: Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        preventStealing: false
        propagateComposedEvents: true

        onPressed: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                Quickshell.execDetached([
                    "hyprctl","dispatch","exec",
                    "[float;size 1100 800;center] thunderbird -calendar "
                ])
                GlobalStates.sidebarRightOpen = false
                mouse.accepted = true;
            } else {
                mouse.accepted = false; // let left-clicks reach buttons
            }
        }
    }
}
