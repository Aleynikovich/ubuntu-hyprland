import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "calendar_layout.js" as CalendarLayout
import QtQuick
import QtQuick.Layouts

Item {
    // Layout.topMargin: 10
    anchors.topMargin: 10
    property int monthShift: 0
    property var viewingDate: CalendarLayout.getDateInXMonthsTime(monthShift)
    property var calendarLayout: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0)
    // Google/ICS events (services/CalendarEvents.qml): dots under days with events; clicking a day opens its agenda
    property var selectedDate: null
    property bool showAgenda: selectedDate !== null
    property var weekdayOffset: (new Date(viewingDate.getFullYear(), viewingDate.getMonth(), 1).getDay() + 6) % 7
    function cellDate(row, col) {
        return new Date(viewingDate.getFullYear(), viewingDate.getMonth(), 1 - weekdayOffset + row * 7 + col);
    }
    width: calendarColumn.width
    implicitHeight: calendarColumn.height + 10 * 2

    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)
            && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown) {
                monthShift++;
            } else if (event.key === Qt.Key_PageUp) {
                monthShift--;
            }
            event.accepted = true;
        }
    }
    MouseArea {
        anchors.fill: parent
        onWheel: (event) => {
            if (showAgenda) return;
            if (event.angleDelta.y > 0) {
                monthShift--;
            } else if (event.angleDelta.y < 0) {
                monthShift++;
            }
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
                buttonText: showAgenda ? `‹ ${selectedDate.toLocaleDateString(Qt.locale(), "dddd, d MMMM")}`
                    : `${monthShift != 0 ? "• " : ""}${viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")}`
                tooltipText: showAgenda ? Translation.tr("Back to the month") : (monthShift === 0) ? "" : Translation.tr("Jump to current month")
                downAction: () => {
                    if (showAgenda) {
                        selectedDate = null;
                    } else {
                        monthShift = 0;
                    }
                }
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: false
            }
            CalendarHeaderButton {
                forceCircle: true
                downAction: () => {
                    monthShift--;
                }
                contentItem: MaterialSymbol {
                    text: "chevron_left"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
            CalendarHeaderButton {
                forceCircle: true
                downAction: () => {
                    monthShift++;
                }
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
            visible: !showAgenda
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: false
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
            // model: calendarLayout
            model: 6
            delegate: RowLayout {
                visible: !showAgenda
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                spacing: 5
                Repeater {
                    model: Array(7).fill(modelData)
                    delegate: CalendarDayButton {
                        day: calendarLayout[modelData][index].day
                        isToday: calendarLayout[modelData][index].today
                        eventCount: CalendarEvents.eventsOn(cellDate(modelData, index)).length
                        onClicked: selectedDate = cellDate(modelData, index)
                    }
                }
            }
        }

        // Selected day's events
        ListView {
            id: agenda
            visible: showAgenda
            Layout.fillWidth: true
            Layout.preferredHeight: 38 * 7 + 5 * 6
            clip: true
            spacing: 4
            model: showAgenda ? CalendarEvents.eventsOn(selectedDate) : []
            delegate: Rectangle {
                required property var modelData
                width: agenda.width
                implicitHeight: eventRow.implicitHeight + 12
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                RowLayout {
                    id: eventRow
                    anchors { fill: parent; margins: 6 }
                    spacing: 8
                    StyledText {
                        Layout.preferredWidth: 78
                        text: modelData.allDay ? Translation.tr("All day") : `${modelData.start} – ${modelData.end}`
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.title
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: modelData.location.length > 0
                            text: modelData.location
                            elide: Text.ElideRight
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }
            }
            StyledText {
                anchors.centerIn: parent
                visible: agenda.count === 0
                color: Appearance.colors.colSubtext
                text: CalendarEvents.failed ? Translation.tr("Could not read the calendar feed")
                    : !CalendarEvents.loaded ? Translation.tr("Loading…") : Translation.tr("No events")
            }
        }
    }
}
