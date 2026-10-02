import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
    id: root
    moduleName: "nick.quick-settings"
    ipcTarget: "nick.quick-settings"
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    readonly property color foreground: bar ? bar.foreground : Color.foreground
    readonly property string script: Qt.resolvedUrl("settings.py").toString().replace(/^file:\/\//, "")
    property var plugins: []
    property var selected: []
    property var draft: []
    property bool editing: false
    property bool busy: false
    property string error: ""
    property string filter: ""
    readonly property var tiles: {
        var out = []
        for (var i = 0; i < selected.length; i++) {
            var found = plugins.find(function(p) { return p.id === selected[i] })
            if (found) out.push(found)
        }
        return out
    }
    readonly property var available: plugins.filter(function(p) {
        return (p.name + " " + p.description).toLowerCase().indexOf(root.filter.toLowerCase()) !== -1
    })

    function refresh() { if (!status.running && !busy) status.running = true }
    function update(text) {
        try {
            var result = JSON.parse(text)
            if (result.error) { error = result.error; return }
            if (result.plugins) {
                plugins = result.plugins
                selected = result.selected
            }
            error = ""
        } catch (e) { error = "Unable to read plugin list" }
    }
    function action(args) {
        if (busy) return
        busy = true
        error = ""
        control.command = ["python3", script].concat(args)
        control.running = true
    }
    function select(id) {
        var next = draft.slice()
        var index = next.indexOf(id)
        if (index === -1) next.push(id)
        else next.splice(index, 1)
        draft = next
    }
    function edit() { draft = selected.slice(); filter = ""; editing = true; refresh() }
    function openPlugin(plugin) {
        if (!plugin.enabled) { error = "Enable " + plugin.name + " in Edit plugins first"; return }
        close()
        // Let the focus grab and closing animation settle before opening another panel.
        pendingPlugin = plugin.id
        launchTimer.restart()
    }
    property string pendingPlugin: ""
    Timer { id: launchTimer; interval: 180; onTriggered: root.action(["open", root.pendingPlugin]) }
    onOpenedChanged: {
        if (opened && error === "") refresh()
        else { editing = false; filter = "" }
    }
    Process {
        id: status
        command: ["python3", root.script, "sync"]
        stdout: StdioCollector { onStreamFinished: root.update(text) }
    }
    Timer {
        interval: 5000
        repeat: true
        running: root.opened && !root.editing
        onTriggered: { if (!iconStatus.running && !status.running && !root.busy) iconStatus.running = true }
    }
    Process {
        id: iconStatus
        command: ["python3", root.script, "status"]
        stdout: StdioCollector { onStreamFinished: root.update(text) }
    }
    Process {
        id: control
        property var result: ({})
        stdout: StdioCollector {
            onStreamFinished: {
                try { control.result = JSON.parse(text) } catch (e) { control.result = { error: "Plugin command failed" } }
                root.update(text)
            }
        }
        onExited: function(code, status) {
            root.busy = false
            if (control.result.error || code !== 0) {
                if (!root.error) root.error = "Plugin command failed"
                if (!root.opened) root.open()
            } else if (control.command[2] === "save") root.editing = false
        }
    }
    IpcHandler {
        target: "nick.quick-settings-actions"
        function edit(): void { root.open(); root.edit() }
        function refresh(): void { root.refresh() }
        function inspect(): string { return JSON.stringify({ opened: root.opened, count: root.tiles.length, editing: root.editing, error: root.error }) }
        function launch(id: string): void {
            var plugin = root.plugins.find(function(p) { return p.id === id })
            if (plugin) root.openPlugin(plugin)
        }
    }
    Component.onCompleted: refresh()

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "󰒓"
        active: root.opened
        activeColor: Color.accent
        useActiveColor: true
        tooltipText: "Quick Settings · " + root.tiles.length + " plugins\nRight-click to edit"
        onPressed: function(btn) {
            if (btn === Qt.RightButton) { root.open(); root.edit() }
            else root.toggle()
        }
    }
    PopupCard {
        anchorItem: button
        bar: root.bar
        owner: root
        open: root.opened
        id: popup
        contentWidth: Style.space(480)
        contentHeight: Math.min(Style.space(root.editing ? 580 : Math.max(350, 140 + Math.ceil(root.tiles.length / 3) * 90)), Math.max(200, availableCardHeight - verticalContentInset))
        ColumnLayout {
            anchors.fill: parent
            spacing: Style.space(12)
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: root.editing ? "Choose plugins" : "Quick Settings"
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.display
                    font.bold: true
                }
                PanelActionButton {
                    iconText: "󰑐"
                    tooltipText: "Refresh installed plugins"
                    focusable: true
                    enabled: !root.busy
                    onClicked: root.refresh()
                }
                PanelActionButton {
                    iconText: root.editing ? "󰅖" : "󰏫"
                    tooltipText: root.editing ? "Cancel changes" : "Edit plugins"
                    focusable: true
                    enabled: !root.busy
                    onClicked: root.editing ? root.editing = false : root.edit()
                }
            }
            Text {
                Layout.fillWidth: true
                text: root.editing ? "Selected plugins appear here instead of in the bar." : root.tiles.length + " selected plugins"
                color: root.foreground
                opacity: 0.65
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
            }
            Text {
                Layout.fillWidth: true
                visible: root.error !== ""
                text: root.error
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Color.urgent
                font.pixelSize: Style.font.caption
            }
            TextField {
                Layout.fillWidth: true
                visible: root.editing
                placeholderText: "Search plugins…"
                text: root.filter
                onTextChanged: root.filter = text
            }
            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.editing
                clip: true
                cellWidth: (width - Style.space(12)) / 3
                cellHeight: Style.space(90)
                model: root.tiles
                Controls.ScrollBar.vertical: Controls.ScrollBar {
                    policy: Controls.ScrollBar.AlwaysOn
                    visible: grid.contentHeight > grid.height
                }
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    width: grid.cellWidth - Style.space(8)
                    height: grid.cellHeight - Style.space(8)
                    radius: Style.cornerRadius
                    color: tileMouse.containsMouse || activeFocus ? Style.hoverFillFor(root.foreground, Color.accent) : Style.normalFillFor(root.foreground, Color.accent)
                    border.width: 1
                    border.color: Qt.alpha(root.foreground, 0.15)
                    opacity: modelData.enabled ? 1 : 0.5
                    activeFocusOnTab: true
                    Keys.onReturnPressed: root.openPlugin(modelData)
                    Keys.onSpacePressed: root.openPlugin(modelData)
                    Column {
                        anchors.centerIn: parent
                        width: parent.width - Style.space(16)
                        spacing: Style.space(5)
                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Style.space(60)
                            height: Style.space(26)
                            source: tile.modelData.iconSource || ""
                            visible: status === Image.Ready
                            cache: false
                            fillMode: Image.PreserveAspectFit
                        }
                        Text {
                            visible: !tile.modelData.iconSource
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.modelData.icon
                            font.family: Style.font.family
                            font.pixelSize: Style.space(26)
                            color: Color.accent
                        }
                        Text {
                            width: parent.width
                            text: tile.modelData.name
                            textFormat: Text.PlainText
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: root.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                        }
                    }
                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !root.busy
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openPlugin(tile.modelData)
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: root.tiles.length === 0
                    text: status.running ? "Loading plugins…" : "Choose plugins with the edit button above."
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                }
            }
            Text {
                Layout.fillWidth: true
                visible: !root.editing && grid.contentHeight > grid.height
                text: "Scroll to see all " + root.tiles.length + " plugins"
                horizontalAlignment: Text.AlignHCenter
                color: root.foreground
                opacity: 0.7
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
            }
            ListView {
                id: choices
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.editing
                clip: true
                spacing: Style.space(5)
                model: root.available
                delegate: Rectangle {
                    id: choice
                    required property var modelData
                    readonly property bool chosen: root.draft.indexOf(modelData.id) !== -1
                    width: choices.width
                    height: Style.space(54)
                    radius: Style.cornerRadius
                    color: chosen ? Style.selectedFillFor(root.foreground, Color.accent) : choiceMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                    activeFocusOnTab: true
                    Keys.onReturnPressed: root.select(modelData.id)
                    Keys.onSpacePressed: root.select(modelData.id)
                    MouseArea {
                        id: choiceMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !root.busy
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.select(choice.modelData.id)
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Style.space(8)
                        Text {
                            text: choice.chosen ? "󰄬" : "󰄱"
                            color: choice.chosen ? Color.accent : root.foreground
                            font.pixelSize: Style.space(20)
                            font.family: Style.font.family
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: choice.modelData.name
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: root.foreground
                                font.family: Style.font.family
                                font.pixelSize: Style.font.body
                            }
                            Text {
                                text: choice.modelData.enabled ? "Enabled" : "Disabled"
                                color: root.foreground
                                opacity: 0.55
                                font.family: Style.font.family
                                font.pixelSize: Style.font.caption
                            }
                        }
                        PanelActionButton {
                            visible: !choice.modelData.enabled
                            iconText: "󰐊"
                            tooltipText: "Enable plugin"
                            focusable: true
                            enabled: !root.busy
                            onClicked: root.action(["enable", choice.modelData.id])
                        }
                    }
                }
            }
            RowLayout {
                visible: root.editing
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: root.draft.length + " selected"
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                }
                Rectangle {
                    implicitWidth: Style.space(120)
                    implicitHeight: Style.space(36)
                    radius: Style.cornerRadius
                    color: Color.accent
                    activeFocusOnTab: true
                    Keys.onReturnPressed: root.action(["save", JSON.stringify(root.draft)])
                    Text {
                        anchors.centerIn: parent
                        text: root.busy ? "Saving…" : "Save selection"
                        color: Color.background
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.busy
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.action(["save", JSON.stringify(root.draft)])
                    }
                }
            }
        }
    }
}
