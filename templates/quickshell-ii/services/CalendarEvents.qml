pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Read-only calendar events for the sidebar calendar, from bin/ii-calendar-agenda (installed as ~/.local/bin/ii-calendar-agenda).
 * `events` maps "yyyy-MM-dd" to [{title, location, allDay, start, end, source}]. Sources: ~/.config/ii-calendar/sources.
 */
Singleton {
    id: root
    property var events: ({})
    property bool loaded: false
    property bool failed: false

    function key(d: date): string {
        return Qt.formatDate(d, "yyyy-MM-dd");
    }
    function eventsOn(d: date): var {
        return root.events[key(d)] ?? [];
    }
    function refresh(): void {
        if (!fetcher.running) fetcher.running = true;
    }

    Timer {
        interval: 15 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: fetcher
        command: ["bash", "-c", "exec \"$HOME/.local/bin/ii-calendar-agenda\""]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.events = JSON.parse(text);
                    root.failed = false;
                } catch (e) {
                    root.failed = true;
                }
                root.loaded = true;
            }
        }
    }
}
