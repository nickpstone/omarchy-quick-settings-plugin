import Quickshell.Io
import QtQuick
import qs.Commons

// Keep the native plugin instance and its IPC alive without reserving bar space.
Item {
    id: root
    property QtObject bar: null
    property string moduleName: ""
    property var settings: ({})
    property string nativeSource: ""
    readonly property bool hubPresent: {
        var layout = bar && bar.layoutConfig ? bar.layoutConfig : {}
        return ["left", "center", "right"].some(function(section) {
            return (layout[section] || []).some(function(entry) {
                return (typeof entry === "string" ? entry : entry.id) === "nick.quick-settings"
            })
        })
    }
    readonly property bool grouped: settings.quickSettingsHidden === true && hubPresent
    readonly property bool opened: native.item ? native.item.opened === true : false
    readonly property bool popoutSwitchClosing: native.item ? native.item.popoutSwitchClosing === true : false
    implicitWidth: grouped ? 0 : native.item && native.item.visible ? native.item.implicitWidth : 0
    implicitHeight: grouped ? 0 : native.item && native.item.visible ? native.item.implicitHeight : 0
    clip: grouped
    function refresh() { if (native.item && typeof native.item.refresh === "function") native.item.refresh() }

    IpcHandler {
        target: "nick.quick-settings-host." + root.moduleName
        function exportIcon(path: string): bool { return root.exportBarIcon(path) }
        function inspect(): string {
            return JSON.stringify({ grouped: root.grouped, opened: root.opened,
                buttons: root.protectedButtons.map(function(button) {
                    return { concealed: button.concealed, interactive: button.interactive, text: button.text || "" }
                }) })
        }
    }
    function exportBarIcon(path) {
        if (protectedButtons.length === 0) return false
        var button = protectedButtons[0]
        var canvas = null
        var children = button.children || []
        for (var i = 0; i < children.length; i++) {
            var parts = children[i].children || []
            for (var j = 0; j < parts.length; j++) {
                if ("sourceComponent" in parts[j] && "iconComponent" in button && parts[j].sourceComponent === button.iconComponent) canvas = children[i]
            }
        }
        if (!canvas || canvas.width <= 0 || canvas.height <= 0) return false
        var target = canvas
        if (button.iconComponent === null) {
            var glyphs = canvas.children || []
            for (var k = 0; k < glyphs.length; k++) {
                if ("tightWidth" in glyphs[k]) {
                    var labels = glyphs[k].children || []
                    for (var n = 0; n < labels.length; n++) {
                        if ("text" in labels[n] && "font" in labels[n]) target = labels[n]
                    }
                }
            }
        }
        return target.grabToImage(function(result) { result.saveToFile(path) },
            Qt.size(Math.max(1, Math.round(target.width * 4)), Math.max(1, Math.round(target.height * 4))))
    }
    function open() { if (native.item && typeof native.item.open === "function") native.item.open() }
    function close() { if (native.item && typeof native.item.close === "function") native.item.close() }
    function closeForPopoutSwitch() {
        if (native.item && typeof native.item.closeForPopoutSwitch === "function") native.item.closeForPopoutSwitch()
        else close()
    }
    property var protectedButtons: []
    function protectBarButtons(item) {
        if (!item) return
        if (typeof item.triggerPress === "function" && "concealed" in item && "interactive" in item && protectedButtons.indexOf(item) === -1) {
            var wasConcealed = item.concealed
            var wasInteractive = item.interactive
            item.concealed = Qt.binding(function() { return root.grouped || wasConcealed })
            item.interactive = Qt.binding(function() { return !root.grouped && wasInteractive })
            protectedButtons = protectedButtons.concat([item])
        }
        var children = item.children || []
        for (var i = 0; i < children.length; i++) protectBarButtons(children[i])
    }
    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: root.protectBarButtons(native.item)
    }
    function inject() {
        if (!native.item) return
        if ("bar" in native.item) native.item.bar = bar
        if ("moduleName" in native.item) native.item.moduleName = moduleName
        if ("settings" in native.item) {
            var clean = {}
            for (var key in settings) {
                if (key !== "quickSettingsHidden" && key !== "quickSettingsRestore" && key !== "source" && key !== "type") clean[key] = settings[key]
            }
            native.item.settings = clean
        }
        protectBarButtons(native.item)
        Qt.callLater(function() { root.protectBarButtons(native.item) })
    }
    onBarChanged: inject()
    onModuleNameChanged: inject()
    onSettingsChanged: inject()
    Loader {
        id: native
        source: root.nativeSource
        width: item ? item.implicitWidth : 0
        height: item ? item.implicitHeight : 0
        onLoaded: { root.inject(); Qt.callLater(root.inject) }
    }
}
