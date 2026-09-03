pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    readonly property string socketPath: root.runtimeDir.length > 0
        ? `${root.runtimeDir}/ii-settingsd/daemon.sock`
        : ""
    readonly property bool connected: daemonSocket.connected
    property string lastError: ""
    property int nextRequestId: 1
    property int retryAttempt: 0
    property var pendingCallbacks: ({})
    property var pendingStartedAt: ({})
    readonly property int requestTimeoutMs: 10000
    property var snapshot: ({})
    property var capabilities: ({})
    property double lastUpdated: 0

    signal actionFinished(string method, bool success, string message)

    function startService() {
        Quickshell.execDetached(["systemctl", "--user", "start", "ii-settingsd.service"])
    }

    function connectSocket() {
        if (root.socketPath.length === 0)
            return
        daemonSocket.connected = true
    }

    function scheduleReconnect() {
        if (reconnectTimer.running)
            return
        daemonSocket.connected = false
        const delay = Math.min(30000, 350 * Math.pow(2, Math.min(root.retryAttempt, 6)))
        root.retryAttempt += 1
        reconnectTimer.interval = delay
        reconnectTimer.restart()
    }

    function request(method, params = ({}), callback = null) {
        if (!root.connected) {
            root.startService()
            root.scheduleReconnect()
            if (typeof callback === "function")
                Qt.callLater(() => callback(null, { code: "offline", message: "Native settings service is offline" }))
            return -1
        }

        const id = root.nextRequestId++
        const callbacks = Object.assign({}, root.pendingCallbacks)
        const startedAt = Object.assign({}, root.pendingStartedAt)
        callbacks[String(id)] = callback
        startedAt[String(id)] = Date.now()
        root.pendingCallbacks = callbacks
        root.pendingStartedAt = startedAt
        daemonSocket.write(JSON.stringify({ id: id, method: method, params: params ?? ({}) }) + "\n")
        daemonSocket.flush()
        return id
    }

    function handleLine(line) {
        const raw = String(line ?? "").trim()
        if (raw.length === 0)
            return

        let message
        try {
            message = JSON.parse(raw)
        } catch (error) {
            root.lastError = "Native settings service returned invalid data"
            return
        }

        if (message.id === undefined || message.id === null)
            return
        const key = String(message.id)
        const callback = root.pendingCallbacks[key]
        const callbacks = Object.assign({}, root.pendingCallbacks)
        const startedAt = Object.assign({}, root.pendingStartedAt)
        delete callbacks[key]
        delete startedAt[key]
        root.pendingCallbacks = callbacks
        root.pendingStartedAt = startedAt

        if (typeof callback === "function") {
            if (message.ok === true)
                callback(message.result ?? ({}), null)
            else
                callback(null, message.error ?? { code: "unknown", message: "Native settings request failed" })
        }
    }

    function failPending(message) {
        const callbacks = root.pendingCallbacks
        root.pendingCallbacks = ({})
        root.pendingStartedAt = ({})
        for (const key of Object.keys(callbacks)) {
            const callback = callbacks[key]
            if (typeof callback === "function")
                callback(null, { code: "disconnected", message: message })
        }
    }

    function expirePending() {
        const now = Date.now()
        const callbacks = Object.assign({}, root.pendingCallbacks)
        const startedAt = Object.assign({}, root.pendingStartedAt)
        let changed = false
        for (const key of Object.keys(startedAt)) {
            if (now - startedAt[key] < root.requestTimeoutMs)
                continue
            const callback = callbacks[key]
            delete callbacks[key]
            delete startedAt[key]
            changed = true
            if (typeof callback === "function")
                callback(null, { code: "timeout", message: "Native settings request timed out" })
        }
        if (changed) {
            root.pendingCallbacks = callbacks
            root.pendingStartedAt = startedAt
            root.lastError = "Native settings service did not respond"
        }
    }

    function refresh() {
        root.request("snapshot", {}, (result, error) => {
            if (error) {
                root.lastError = error.message ?? "System snapshot failed"
                return
            }
            root.snapshot = result
            root.capabilities = result.capabilities ?? root.capabilities
            root.lastUpdated = Date.now()
            root.lastError = ""
        })
    }

    function refreshCapabilities() {
        root.request("capabilities", {}, (result, error) => {
            if (error) {
                root.lastError = error.message ?? "Capability discovery failed"
                return
            }
            root.capabilities = result
        })
    }

    function runAction(method, params = ({}), refreshAfter = true) {
        root.request(method, params, (result, error) => {
            const ok = !error
            const message = ok ? "" : (error.message ?? "Action failed")
            root.lastError = message
            root.actionFinished(method, ok, message)
            if (ok && refreshAfter)
                refreshDelay.restart()
        })
    }

    Socket {
        id: daemonSocket
        path: root.socketPath
        parser: SplitParser {
            splitMarker: "\n"
            onRead: data => root.handleLine(data)
        }

        onConnectionStateChanged: {
            if (daemonSocket.connected) {
                root.retryAttempt = 0
                root.lastError = ""
                Qt.callLater(() => {
                    root.refresh()
                    root.refreshCapabilities()
                })
            } else {
                root.failPending("Native settings service disconnected")
                root.scheduleReconnect()
            }
        }

        onError: error => {
            root.lastError = "Native settings service unavailable"
            root.scheduleReconnect()
        }
    }

    Timer {
        id: reconnectTimer
        repeat: false
        onTriggered: root.connectSocket()
    }

    Timer {
        id: refreshDelay
        interval: 350
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        interval: 1000
        repeat: true
        running: Object.keys(root.pendingStartedAt).length > 0
        onTriggered: root.expirePending()
    }

    Component.onCompleted: {
        root.startService()
        reconnectTimer.interval = 200
        reconnectTimer.start()
    }
}
