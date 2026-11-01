pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property bool available: Bluetooth.adapters.values.length > 0
    readonly property bool enabled: Bluetooth.defaultAdapter?.enabled ?? false
    readonly property BluetoothDevice firstActiveDevice: Bluetooth.defaultAdapter?.devices.values.find(device => device.connected) ?? null
    readonly property int activeDeviceCount: Bluetooth.defaultAdapter?.devices.values.filter(device => device.connected).length ?? 0
    readonly property bool connected: Bluetooth.devices.values.some(d => d.connected)

    function sortFunction(a, b) {
        // Ones with meaningful names before MAC addresses
        const macRegex = /^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$/;
        const aIsMac = macRegex.test(a.name);
        const bIsMac = macRegex.test(b.name);
        if (aIsMac !== bIsMac)
            return aIsMac ? 1 : -1;

        // Alphabetical by name
        return a.name.localeCompare(b.name);
    }
    property list<var> connectedDevices: Bluetooth.devices.values.filter(d => d.connected).sort(sortFunction)
    property list<var> pairedButNotConnectedDevices: Bluetooth.devices.values.filter(d => d.paired && !d.connected).sort(sortFunction)
    property list<var> unpairedDevices: Bluetooth.devices.values.filter(d => !d.paired && !d.connected).sort(sortFunction)
    // The three groups above re-sort on every property change of every nearby device (names resolving, signal updates during discovery),
    // which made rows jump under the cursor. The list the dialog shows is a snapshot taken once things have settled for a moment.
    property list<var> friendlyDeviceList: []
    function snapshot() {
        friendlyDeviceList = [...connectedDevices, ...pairedButNotConnectedDevices, ...unpairedDevices];
    }
    onConnectedDevicesChanged: settle.restart()
    onPairedButNotConnectedDevicesChanged: settle.restart()
    onUnpairedDevicesChanged: settle.restart()
    Timer {
        id: settle
        interval: 400
        onTriggered: root.snapshot()
    }
    Component.onCompleted: snapshot()
}
