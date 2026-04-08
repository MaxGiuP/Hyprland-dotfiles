pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit

Singleton {
    id: root
    property alias agent: polkitAgent
    property alias active: polkitAgent.isActive
    property alias flow: polkitAgent.flow
    property bool interactionAvailable: false
    property string failureMessage: ""
    property bool failureIsLockout: false
    property string cleanMessage: {
        if (!root.flow) return "";
        return root.flow.message.endsWith(".")
            ? root.flow.message.slice(0, -1)
            : root.flow.message
    }
    property string cleanPrompt: {
        const inputPrompt = PolkitService.flow?.inputPrompt.trim() ?? "";
        const cleanedInputPrompt = inputPrompt.endsWith(":") ? inputPrompt.slice(0, -1) : inputPrompt;
        const usePasswordChars = !PolkitService.flow?.responseVisible ?? true
        return cleanedInputPrompt || (usePasswordChars ? Translation.tr("Password") : Translation.tr("Input"))
    }

    function cancel() {
        root.failureMessage = "";
        root.failureIsLockout = false;
        root.flow.cancelAuthenticationRequest()
    }

    function submit(string) {
        root.failureMessage = "";
        root.failureIsLockout = false;
        root.flow.submit(string)
        root.interactionAvailable = false
    }

    Process {
        id: faillockCheckProc
        command: ["bash", "-lc",
            "deny=$(sed -nE 's/^[[:space:]]*deny[[:space:]]*=[[:space:]]*([0-9]+).*$/\\1/p' /etc/security/faillock.conf 2>/dev/null | head -n1); " +
            "[ -n \"$deny\" ] || deny=3; " +
            "count=$(faillock --user \"${USER:-$(id -un)}\" 2>/dev/null | awk 'NR > 1 && /[[:space:]]V[[:space:]]*$/ { count++ } END { print count + 0 }'); " +
            "if [ \"${count:-0}\" -ge \"${deny:-3}\" ]; then echo lockout; else echo incorrect; fi"
        ]
        stdout: StdioCollector {
            id: faillockCheckOut
            onStreamFinished: {
                const result = faillockCheckOut.text.trim();
                root.failureIsLockout = result === "lockout";
                root.failureMessage = root.failureIsLockout
                    ? Translation.tr("Authentication locked after too many failed password attempts. Try again later.")
                    : Translation.tr("Incorrect password");
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.failureIsLockout = false;
                root.failureMessage = Translation.tr("Incorrect password");
            }
        }
    }

    Connections {
        target: root.flow
        function onAuthenticationFailed() {
            root.interactionAvailable = true;
            faillockCheckProc.running = false;
            faillockCheckProc.running = true;
        }
    }

    PolkitAgent {
        id: polkitAgent
        onAuthenticationRequestStarted: {
            root.interactionAvailable = true;
            root.failureMessage = "";
            root.failureIsLockout = false;
        }
    }
}
