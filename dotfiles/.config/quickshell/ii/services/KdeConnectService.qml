pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var devices: []
    property string lastError: ""
    property bool loading: true
    readonly property string statePath: `${Quickshell.env("XDG_RUNTIME_DIR")}/linmax-desktop-bridge/kdeconnect.json`

    function normalizedString(value) {
        return String(value ?? "").trim();
    }

    function notificationLooksSmsRelated(notif) {
        const haystack = [
            root.normalizedString(notif?.appName),
            root.normalizedString(notif?.title),
            root.normalizedString(notif?.ticker),
        ].join(" ").toLowerCase();
        return ["messaggi", "messages", "google messages", "sms"].some(keyword => haystack.includes(keyword));
    }

    function notificationLooksRedacted(notif) {
        const haystack = [
            root.normalizedString(notif?.title),
            root.normalizedString(notif?.text),
            root.normalizedString(notif?.ticker),
        ].join("\n").toLowerCase();
        return [
            "contenuti sensibili della notifica nascosti",
            "contenuti sensibili della notifica nascosto",
            "contenuti sensibili",
            "notifica nascosti",
            "notifica nascosto",
            "sensitive content hidden",
            "sensitive notification content hidden",
            "notification content hidden",
            "notification contents hidden",
            "contents hidden",
        ].some(phrase => haystack.includes(phrase));
    }

    function smsLooksOtp(body) {
        const text = root.normalizedString(body);
        const lower = text.toLowerCase();
        return /\b\d{4,10}\b/.test(text)
            && /(otp|code|codice|password|verification|verify|security|login|access|auth|autentic|one[- ]time)/.test(lower);
    }

    function smsFallbackForNotification(device, notif) {
        if (!device?.available || !root.notificationLooksSmsRelated(notif) || !root.notificationLooksRedacted(notif))
            return null;

        const conversations = (device.smsConversations ?? []).filter(message =>
            !message?.sent && root.normalizedString(message?.body).length > 0
        );
        if (conversations.length === 0)
            return null;

        const now = Date.now();
        const recentMessages = conversations.filter(message => Number(message?.timestamp ?? 0) > now - 30 * 60 * 1000);
        const candidatePool = recentMessages.length > 0 ? recentMessages : conversations;
        const unreadMessages = candidatePool.filter(message => !message?.read);
        const otpUnreadMessages = unreadMessages.filter(message => root.smsLooksOtp(message?.body));
        const otpMessages = candidatePool.filter(message => root.smsLooksOtp(message?.body));
        const chosenMessage = otpUnreadMessages[0] ?? unreadMessages[0] ?? otpMessages[0] ?? candidatePool[0] ?? null;
        if (!chosenMessage)
            return null;

        return {
            "summary": root.normalizedString(chosenMessage?.contact) || root.normalizedString(notif?.appName),
            "body": root.normalizedString(chosenMessage?.body),
        };
    }

    // All phone notifications from available (connected) devices
    readonly property var phoneNotifications: {
        const result = [];
        for (const device of root.devices) {
            if (!device.available) continue;
            for (const notif of (device.notifications ?? [])) {
                const smsFallback = root.smsFallbackForNotification(device, notif);
                result.push({
                    "deviceName": device.name,
                    "deviceId": device.id,
                    "appName": notif.appName ?? "",
                    "title": notif.title ?? "",
                    "text": notif.text ?? "",
                    "ticker": notif.ticker ?? "",
                    "iconPath": notif.iconPath ?? "",
                    "smsFallbackSummary": smsFallback?.summary ?? "",
                    "smsFallbackBody": smsFallback?.body ?? "",
                });
            }
        }
        return result;
    }

    // showPopup=false for notifications already present on startup, true for new arrivals
    signal newPhoneNotification(notif: var, showPopup: bool)
    property var _seenNotifKeys: ({})
    property bool _kdeConnectInitialized: false

    onPhoneNotificationsChanged: {
        const currentKeys = {};
        for (const notif of phoneNotifications) {
            const key = [
                notif.deviceId,
                notif.appName,
                notif.title,
                notif.text,
                notif.ticker,
                notif.smsFallbackSummary,
                notif.smsFallbackBody,
            ].join("::");
            currentKeys[key] = true;
            if (!root._seenNotifKeys[key]) {
                root.newPhoneNotification(notif, root._kdeConnectInitialized);
            }
        }
        root._seenNotifKeys = currentKeys;
        root._kdeConnectInitialized = true;
    }

    function refresh() {
        root.loading = true;
        stateFile.reload();
        loadingFallback.restart();
    }

    function runAction(args) {
        actionProc.running = false;
        root.lastError = "";
        actionProc.command = ["kdeconnect-cli", ...args];
        actionProc.running = true;
    }

    Timer {
        id: loadingFallback
        interval: 750
        repeat: false
        onTriggered: root.loading = false
    }

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const payload = JSON.parse(stateFile.text() || "{}");
                root.devices = payload.devices ?? [];
                root.lastError = payload.error ?? "";
            } catch (e) {
                root.lastError = `${e}`;
            }
            root.loading = false;
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                root.lastError = `Could not load KDE Connect state: ${error}`;
            root.loading = false;
        }
    }

    Process {
        id: actionProc
        stdout: StdioCollector {
            id: actionOut
            waitForEnd: true
        }

        stderr: StdioCollector {
            id: actionErr
            waitForEnd: true
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.lastError = actionErr.text.trim() || actionOut.text.trim() || `kdeconnect-cli failed with code ${exitCode}`;
            }
            root.refresh();
        }
    }
}
