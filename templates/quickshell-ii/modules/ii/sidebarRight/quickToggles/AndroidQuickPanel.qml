import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

import qs.modules.ii.sidebarRight.quickToggles.androidStyle

AbstractQuickPanel {
    id: root
    property bool editMode: false
    Layout.fillWidth: true

    // Sizes
    implicitHeight: (editMode ? contentItem.implicitHeight : tabbedView.implicitHeight) + root.padding * 2
    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    property real spacing: 6
    property real padding: 6
    readonly property real baseCellWidth: {
        // This is the wrong calculation, but it looks correct in reality???
        // (theoretically spacing should be multiplied by 1 column less)
        const availableWidth = root.width - (root.padding * 2) - (root.spacing * (root.columns))
        return availableWidth / root.columns
    }
    readonly property real baseCellHeight: 56

    // Toggles
    readonly property list<string> availableToggleTypes: ["network", "bluetooth", "idleInhibitor", "easyEffects", "nightLight", "darkMode", "cloudflareWarp", "gameMode", "screenSnip", "colorPicker", "onScreenKeyboard", "mic", "audio", "notifications", "powerProfile","musicRecognition", "antiFlashbang", "vmGpu", "gpuSession", "metered", "vpn", "tailscale"]
    readonly property int columns: Config.options.sidebar.quickToggles.android.columns
    readonly property list<var> toggles: Config.ready ? Config.options.sidebar.quickToggles.android.toggles : []
    readonly property list<var> toggleRows: toggleRowsForList(toggles)
    readonly property list<var> unusedToggles: {
        const types = availableToggleTypes.filter(type => !toggles.some(toggle => (toggle && toggle.type === type)))
        return types.map(type => { return { type: type, size: 1 } })
    }
    readonly property list<var> unusedToggleRows: toggleRowsForList(unusedToggles)

    function toggleRowsForList(togglesList) {
        var rows = [];
        var row = [];
        var totalSize = 0; // Total cols taken in current row
        for (var i = 0; i < togglesList.length; i++) {
            if (!togglesList[i]) continue;
            if (totalSize + togglesList[i].size > columns) {
                rows.push(row);
                row = [];
                totalSize = 0;
            }
            row.push(togglesList[i]);
            totalSize += togglesList[i].size;
        }
        if (row.length > 0) {
            rows.push(row);
        }
        return rows;
    }

    // Tabbed view: toggles grouped by tab, drawn as icon-only cells; the detail strip shows the hovered / clicked cell's label.
    // Edit mode keeps the full, sized layout below so the saved order and sizes stay editable.
    readonly property var tabDefs: [
        { name: Translation.tr("Network"), icon: "lan", types: ["network", "bluetooth", "cloudflareWarp", "vpn", "metered", "tailscale"] },
        { name: Translation.tr("Display"), icon: "monitor", types: ["nightLight", "darkMode", "antiFlashbang", "vmGpu", "gpuSession", "colorPicker", "screenSnip"] },
        { name: Translation.tr("Power"), icon: "bolt", types: ["idleInhibitor", "powerProfile", "gameMode", "notifications"] },
        { name: Translation.tr("Desk"), icon: "headset_mic", types: ["mic", "audio", "onScreenKeyboard", "easyEffects", "musicRecognition"] }
    ]
    function tabIndexOf(type) {
        const i = tabDefs.findIndex(t => t.types.includes(type));
        return i < 0 ? tabDefs.length - 1 : i;
    }
    readonly property list<var> activeTabs: tabDefs.map((t, i) => i).filter(i => toggles.some(t => t && tabIndexOf(t.type) === i))
    property int currentTab: 0
    readonly property int shownTab: activeTabs.includes(currentTab) ? currentTab : (activeTabs[0] ?? 0)
    readonly property list<var> tabToggles: toggles.filter(t => t && tabIndexOf(t.type) === shownTab).map(t => ({ type: t.type, size: 1 }))
    readonly property int gridColumns: 6
    readonly property real gridCell: (root.width - root.padding * 2 - root.spacing * (gridColumns - 1)) / gridColumns

    Column {
        id: tabbedView
        visible: !root.editMode
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.spacing

        Row {
            spacing: root.spacing
            Repeater {
                model: root.activeTabs
                delegate: GroupButton {
                    required property int modelData
                    width: (tabbedView.width - root.spacing * (root.activeTabs.length - 1)) / root.activeTabs.length
                    baseWidth: width
                    baseHeight: 30
                    bounce: false
                    toggled: root.shownTab === modelData
                    buttonRadius: height / 2
                    colBackground: Appearance.colors.colLayer2
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        iconSize: 20
                        fill: parent.toggled ? 1 : 0
                        text: root.tabDefs[parent.modelData].icon
                        color: parent.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                    StyledToolTip {
                        text: root.tabDefs[parent.modelData].name
                    }
                    onClicked: {
                        QuickToggleDetail.item = null;
                        root.currentTab = modelData;
                    }
                }
            }
        }

        Flow {
            width: parent.width
            spacing: root.spacing
            Repeater {
                model: ScriptModel {
                    values: root.tabToggles
                    objectProp: "type"
                }
                delegate: AndroidToggleDelegateChooser {
                    startingIndex: -1
                    editMode: false
                    baseCellWidth: root.gridCell
                    baseCellHeight: root.gridCell
                    spacing: root.spacing
                    onOpenAudioOutputDialog: root.openAudioOutputDialog()
                    onOpenAudioInputDialog: root.openAudioInputDialog()
                    onOpenBluetoothDialog: root.openBluetoothDialog()
                    onOpenNightLightDialog: root.openNightLightDialog()
                    onOpenWifiDialog: root.openWifiDialog()
                }
            }
        }

        Rectangle {
            width: parent.width
            implicitHeight: detailText.implicitHeight + 12
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2

            StyledText {
                id: detailText
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: 10
                }
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer2
                readonly property var item: QuickToggleDetail.item
                text: item ? (item.name + (item.statusText ? " · " + item.statusText : "")) : Translation.tr("Hover an icon for details")
            }
        }
    }

    Column {
        id: contentItem
        visible: root.editMode
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 12
        
        Column {
            id: usedRows
            spacing: root.spacing

            Repeater {
                id: usedRowsRepeater
                model: ScriptModel {
                    values: Array(root.toggleRows.length)
                }
                delegate: ButtonGroup {
                    id: toggleRow
                    required property int index
                    property var modelData: root.toggleRows[index]
                    property int startingIndex: {
                        const rows = root.toggleRows;
                        let sum = 0;
                        for (let i = 0; i < index; i++) {
                            sum += rows[i].length;
                        }
                        return sum;
                    }
                    spacing: root.spacing

                    Repeater {
                        model: ScriptModel {
                            values: toggleRow?.modelData ?? []
                            objectProp: "type"
                        }
                        delegate: AndroidToggleDelegateChooser {
                            startingIndex: toggleRow.startingIndex
                            editMode: root.editMode
                            baseCellWidth: root.baseCellWidth
                            baseCellHeight: root.baseCellHeight
                            spacing: root.spacing
                            onOpenAudioOutputDialog: root.openAudioOutputDialog()
                            onOpenAudioInputDialog: root.openAudioInputDialog()
                            onOpenBluetoothDialog: root.openBluetoothDialog()
                            onOpenNightLightDialog: root.openNightLightDialog()
                            onOpenWifiDialog: root.openWifiDialog()
                        }
                    }
                }
            }
        }

        FadeLoader {
            shown: root.editMode
            anchors {
                left: parent.left
                right: parent.right
                leftMargin: root.baseCellHeight / 2
                rightMargin: root.baseCellHeight / 2
            }
            sourceComponent: Rectangle {
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }
        }

        FadeLoader {
            shown: root.editMode
            sourceComponent: Column {
                id: unusedRows
                spacing: root.spacing

                Repeater {
                    model: ScriptModel {
                        values: Array(root.unusedToggleRows.length)
                    }
                    delegate: ButtonGroup {
                        id: unusedToggleRow
                        required property int index
                        property var modelData: root.unusedToggleRows[index]
                        spacing: root.spacing

                        Repeater {
                            model: ScriptModel {
                                values: unusedToggleRow?.modelData ?? []
                                objectProp: "type"
                            }
                            delegate: AndroidToggleDelegateChooser {
                                startingIndex: -1
                                editMode: root.editMode
                                baseCellWidth: root.baseCellWidth
                                baseCellHeight: root.baseCellHeight
                                spacing: root.spacing
                            }
                        }
                    }
                }
            }
        }
    }
}
