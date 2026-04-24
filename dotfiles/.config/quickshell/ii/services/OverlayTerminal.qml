pragma Singleton

import QtQuick
import Quickshell
import QMLTermWidget 2.0

Singleton {
    id: root

    property var session: null
    property bool started: false
    property bool displayReady: false
    property var queuedCommands: []
    property int handledOverlayCommandNonce: 0

    function ensureSession() {
        if (root.session)
            return root.session

        return root.createSession()
    }

    function createSession(startImmediately = false) {
        const previousSession = root.session
        const nextSession = termSessionComponent.createObject(root)

        if (!nextSession) {
            console.warn("[OverlayTerminal] Failed to create terminal session")
            return null
        }

        nextSession.finished.connect(function() {
            if (root.session !== nextSession)
                return

            root.started = false
            root.displayReady = false
        })

        root.session = nextSession
        root.started = false
        root.displayReady = false

        if (startImmediately)
            root.ensureStarted()

        if (previousSession)
            previousSession.destroy()

        return nextSession
    }

    function ensureStarted() {
        const currentSession = root.ensureSession()
        if (!currentSession)
            return

        if (root.started)
            return

        currentSession.startShellProgram()
        root.started = true
    }

    function queueCommand(cmd) {
        const trimmed = (cmd ?? "").trim()
        if (!trimmed)
            return

        if (!root.queuedCommands.includes(trimmed))
            root.queuedCommands = root.queuedCommands.concat([trimmed])
    }

    function flushQueuedCommands() {
        const currentSession = root.session
        if (!root.started || !currentSession || root.queuedCommands.length === 0)
            return

        const pending = root.queuedCommands.slice()
        root.queuedCommands = []
        for (const cmd of pending)
            currentSession.sendText(cmd + "\n")
    }

    function runCommand(cmd) {
        const trimmed = (cmd ?? "").trim()
        if (!trimmed)
            return

        root.ensureStarted()
        if (!root.displayReady) {
            root.queueCommand(trimmed)
            return
        }

        root.session.sendText(trimmed + "\n")
    }

    function sendRaw(text) {
        if (!text)
            return

        root.ensureStarted()
        if (!root.displayReady || !root.session)
            return

        root.session.sendText(text)
    }

    function clearTerminal() {
        const shouldRestart = root.started || !!root.session

        root.queuedCommands = []
        root.createSession(shouldRestart)
    }

    function consumePendingOverlayCommand(nonce, command) {
        if (nonce <= root.handledOverlayCommandNonce)
            return false

        root.handledOverlayCommandNonce = nonce
        root.runCommand(command)
        return true
    }

    Component {
        id: termSessionComponent

        QMLTermSession {
            initialWorkingDirectory: Quickshell.env("HOME") || "/"
            shellProgram: "fish"
            shellProgramArgs: ["-i"]
        }
    }

    Component.onCompleted: {
        root.ensureSession()
    }
}
