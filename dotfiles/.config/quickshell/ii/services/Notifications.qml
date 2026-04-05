pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

/**
 * Provides extra features not in Quickshell.Services.Notifications:
 *  - Persistent storage
 *  - Popup notifications, with timeout
 *  - Notification groups by app
 */
Singleton {
	id: root
    component Notif: QtObject {
        id: wrapper
        required property int notificationId // Could just be `id` but it conflicts with the default prop in QtObject
        property Notification notification
        property list<var> actions: notification?.actions.map((action) => ({
            "identifier": action.identifier,
            "text": action.text,
        })) ?? []
        property bool popup: false
        property bool isTransient: notification?.hints.transient ?? false
        property string desktopEntry: notification?.desktopEntry
            ?? notification?.hints?.desktopEntry
            ?? ((notification && notification.hints) ? (notification.hints["desktop-entry"] ?? "") : "")
        property string appIcon: notification?.appIcon ?? ""
        property string appName: notification?.appName ?? ""
        property string body: notification?.body ?? ""
        property string image: notification?.image ?? ""
        property string summary: notification?.summary ?? ""
        property double time
        property string urgency: notification?.urgency.toString() ?? "normal"
        property Timer timer
        property int timeoutDurationMs: 0
        property real timeoutRemainingMs: 0
        property double timeoutStartedAt: 0
        property bool timeoutPaused: false
        property real timeoutProgress: {
            if (!popup || timeoutDurationMs <= 0)
                return 0;

            const liveRemaining = timeoutPaused
                ? timeoutRemainingMs
                : Math.max(0, timeoutRemainingMs - (root.timeoutNow - timeoutStartedAt));
            return Math.max(0, Math.min(1, liveRemaining / timeoutDurationMs));
        }
        property bool isPhoneNotif: false
        property string deviceId: ""
        property string deviceName: ""

        onNotificationChanged: {
            if (notification === null) {
                root.discardNotification(notificationId);
            }
        }
    }

    function notifToJSON(notif) {
        return {
            "notificationId": notif.notificationId,
            "actions": notif.actions,
            "desktopEntry": notif.desktopEntry ?? "",
            "appIcon": notif.appIcon,
            "appName": notif.appName,
            "body": notif.body,
            "image": notif.image,
            "summary": notif.summary,
            "time": notif.time,
            "urgency": notif.urgency,
        }
    }
    function notifToString(notif) {
        return JSON.stringify(notifToJSON(notif), null, 2);
    }

    function phoneNotifSummary(notif) {
        const title = String(notif?.title ?? "").trim();
        const ticker = String(notif?.ticker ?? "").trim();
        return title.length > 0 ? title : ticker;
    }

    function phoneNotifBody(notif) {
        const text = String(notif?.text ?? "").trim();
        if (text.length > 0)
            return text;

        const ticker = String(notif?.ticker ?? "").trim();
        if (ticker.length === 0)
            return "";

        const summary = root.phoneNotifSummary(notif);
        if (summary.length === 0 || ticker === summary)
            return "";

        const summaryPrefixes = [
            `${summary}: `,
            `${summary} - `,
            `${summary}\n`,
        ];
        for (const prefix of summaryPrefixes) {
            if (ticker.startsWith(prefix))
                return ticker.slice(prefix.length).trim();
        }

        return ticker;
    }

    component NotifTimer: Timer {
        required property int notificationId
        interval: 12000
        running: true
        onTriggered: () => {
            root.handleTimerElapsed(notificationId);
            destroy()
        }
    }

    property bool silent: false
    property int unread: 0
    property double timeoutNow: Date.now()
    property var filePath: Directories.notificationsPath
    property list<Notif> list: []
    property var popupList: list.filter((notif) => notif.popup);
    property bool popupInhibited: (GlobalStates?.sidebarRightOpen ?? false) || silent
    property var latestTimeForApp: ({})
    property int _phoneNotifId: 0
    property var phoneNotifList: list.filter((notif) => notif.isPhoneNotif)
    property var phoneNotifGroupsByAppName: groupsForList(root.phoneNotifList)
    property var phoneNotifAppNameList: appNameListForGroups(root.phoneNotifGroupsByAppName)
    Component {
        id: notifComponent
        Notif {}
    }
    Component {
        id: notifTimerComponent
        NotifTimer {}
    }

    Timer {
        id: timeoutProgressTicker
        interval: 50
        repeat: true
        running: true

        onTriggered: {
            if (root.popupList.some((notif) => notif.timeoutDurationMs > 0 && !notif.timeoutPaused))
                root.timeoutNow = Date.now();
        }
    }

    function stringifyList(list) {
        return JSON.stringify(list.filter((notif) => !notif.isPhoneNotif).map((notif) => notifToJSON(notif)), null, 2);
    }

    function effectiveTimeoutInterval(expireTimeout) {
        if (expireTimeout === 0)
            return 0;

        return expireTimeout < 0
            ? (Config?.options.notifications.timeout ?? 12000)
            : expireTimeout;
    }

    function configurePopupTimeout(notif, interval) {
        if (!notif || interval <= 0)
            return;

        notif.timeoutDurationMs = interval;
        notif.timeoutRemainingMs = interval;
        notif.timeoutStartedAt = Date.now();
        notif.timeoutPaused = false;
        root.timeoutNow = notif.timeoutStartedAt;
        notif.timer = notifTimerComponent.createObject(root, {
            "notificationId": notif.notificationId,
            "interval": interval,
        });
    }

    function currentRemainingTimeoutMs(notif) {
        if (!notif || notif.timeoutDurationMs <= 0)
            return 0;

        if (notif.timeoutPaused || !(notif.timer?.running ?? false))
            return Math.max(0, notif.timeoutRemainingMs);

        return Math.max(0, notif.timeoutRemainingMs - (Date.now() - notif.timeoutStartedAt));
    }

    function pauseTimeoutForNotif(notif) {
        if (!notif || !(notif.timer?.running ?? false))
            return;

        notif.timeoutRemainingMs = currentRemainingTimeoutMs(notif);
        notif.timeoutPaused = true;
        notif.timer.stop();
        root.timeoutNow = Date.now();
    }

    function resumeTimeoutForNotif(notif) {
        if (!notif || !notif.popup || notif.timeoutDurationMs <= 0 || notif.timeoutRemainingMs <= 0 || notif.timer == null)
            return;

        notif.timeoutStartedAt = Date.now();
        notif.timeoutPaused = false;
        notif.timer.interval = Math.max(1, Math.round(notif.timeoutRemainingMs));
        notif.timer.start();
        root.timeoutNow = notif.timeoutStartedAt;
    }

    function handleTimerElapsed(notificationId) {
        const notifObject = root.getNotificationById(notificationId);
        print("[Notifications] Notification timer triggered for ID: " + notificationId + ", transient: " + notifObject?.isTransient);
        if (!notifObject)
            return;

        notifObject.timeoutRemainingMs = 0;
        notifObject.timeoutPaused = true;
        notifObject.timer = null;

        if (notifObject.isTransient)
            root.discardNotification(notificationId);
        else
            root.timeoutNotification(notificationId, false);
    }
    
    onListChanged: {
        // Update latest time for each app
        root.list.forEach((notif) => {
            if (!root.latestTimeForApp[notif.appName] || notif.time > root.latestTimeForApp[notif.appName]) {
                root.latestTimeForApp[notif.appName] = Math.max(root.latestTimeForApp[notif.appName] || 0, notif.time);
            }
        });
        // Remove apps that no longer have notifications
        Object.keys(root.latestTimeForApp).forEach((appName) => {
            if (!root.list.some((notif) => notif.appName === appName)) {
                delete root.latestTimeForApp[appName];
            }
        });
    }

    function appNameListForGroups(groups) {
        return Object.keys(groups).sort((a, b) => {
            // Sort by time, descending
            return groups[b].time - groups[a].time;
        });
    }

    function groupsForList(list) {
        const groups = {};
        list.forEach((notif) => {
            if (!groups[notif.appName]) {
                groups[notif.appName] = {
                    appName: notif.appName,
                    appIcon: notif.appIcon,
                    notifications: [],
                    time: 0
                };
            }
            groups[notif.appName].notifications.push(notif);
            // Always set to the latest time in the group
            groups[notif.appName].time = latestTimeForApp[notif.appName] || notif.time;
        });
        return groups;
    }

    property var groupsByAppName: groupsForList(root.list)
    property var popupGroupsByAppName: groupsForList(root.popupList)
    property list<string> appNameList: appNameListForGroups(root.groupsByAppName)
    property list<string> popupAppNameList: appNameListForGroups(root.popupGroupsByAppName)

    // Quickshell's notification IDs starts at 1 on each run, while saved notifications
    // can already contain higher IDs. This is for avoiding id collisions
    property int idOffset
    signal initDone();
    signal notify(notification: var);
    signal discard(id: int);
    signal discardAll();
    signal timeout(id: var);

	NotificationServer {
        id: notifServer
        // actionIconsSupported: true
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        keepOnReload: true
        persistenceSupported: true

        onNotification: (notification) => {
            notification.tracked = true
            const newNotifObject = notifComponent.createObject(root, {
                "notificationId": notification.id + root.idOffset,
                "notification": notification,
                "time": Date.now(),
            });
			root.list = [...root.list, newNotifObject];

            // Popup
            if (!root.popupInhibited) {
                newNotifObject.popup = true;
                const timeoutInterval = root.effectiveTimeoutInterval(notification.expireTimeout);
                root.configurePopupTimeout(newNotifObject, timeoutInterval);
                root.unread++;
            }
            root.notify(newNotifObject);
            // console.log(notifToString(newNotifObject));
            notifFileView.setText(stringifyList(root.list));
        }
    }

    Connections {
        target: KdeConnectService
        function onNewPhoneNotification(notif, showPopup) {
            root._phoneNotifId--;
            const id = root._phoneNotifId;
            const appName = (notif.appName ?? "").length > 0 ? notif.appName : notif.deviceName;
            const summary = root.phoneNotifSummary(notif);
            const body = root.phoneNotifBody(notif);
            const iconPath = notif.iconPath ?? "";
            const newNotifObject = notifComponent.createObject(root, {
                "notificationId": id,
                "appName": appName,
                "summary": summary,
                "body": body,
                "appIcon": iconPath.length > 0 ? iconPath : "material:smartphone",
                "time": Date.now(),
                "isPhoneNotif": true,
                "deviceId": notif.deviceId,
                "deviceName": notif.deviceName,
            });
            root.list = [...root.list, newNotifObject];
            if (showPopup && !root.popupInhibited) {
                newNotifObject.popup = true;
                root.configurePopupTimeout(newNotifObject, Config?.options.notifications.timeout ?? 12000);
                root.unread++;
            }
            root.notify(newNotifObject);
            notifFileView.setText(stringifyList(root.list));
        }
    }

    function markAllRead() {
        root.unread = 0;
    }

    function discardNotification(id) {
        console.log("[Notifications] Discarding notification with ID: " + id);
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        if (index !== -1) {
            if (root.list[index].timer != null) {
                root.list[index].timer.stop();
                root.list[index].timer.destroy();
                root.list[index].timer = null;
            }
            root.list.splice(index, 1);
            notifFileView.setText(stringifyList(root.list));
            triggerListChange()
        }
        if (notifServerIndex !== -1) {
            notifServer.trackedNotifications.values[notifServerIndex].dismiss()
        }
        root.discard(id); // Emit signal
    }

    function discardAllNotifications() {
        root.list = []
        triggerListChange()
        notifFileView.setText(stringifyList(root.list));
        notifServer.trackedNotifications.values.forEach((notif) => {
            notif.dismiss()
        })
        root.discardAll();
    }

    function cancelTimeout(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null)
            pauseTimeoutForNotif(root.list[index]);
    }

    function resumeTimeout(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null)
            resumeTimeoutForNotif(root.list[index]);
    }

    function timeoutNotification(id, destroyTimer = true) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null) {
            if (destroyTimer && root.list[index].timer != null) {
                root.list[index].timer.stop();
                root.list[index].timer.destroy();
                root.list[index].timer = null;
            }
            root.list[index].timeoutRemainingMs = 0;
            root.list[index].timeoutPaused = true;
            root.list[index].popup = false;
            root.timeoutNow = Date.now();
        }
        root.timeout(id);
    }

    function timeoutAll() {
        root.popupList.forEach((notif) => {
            root.timeout(notif.notificationId);
        })
        root.popupList.forEach((notif) => {
            notif.popup = false;
        });
    }

    function attemptInvokeAction(id, notifIdentifier) {
        console.log("[Notifications] Attempting to invoke action with identifier: " + notifIdentifier + " for notification ID: " + id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        console.log("Notification server index: " + notifServerIndex);
        if (notifServerIndex !== -1) {
            const notifServerNotif = notifServer.trackedNotifications.values[notifServerIndex];
            const action = notifServerNotif.actions.find((action) => action.identifier === notifIdentifier);
            // console.log("Action found: " + JSON.stringify(action));
            action.invoke()
        } 
        else {
            console.log("Notification not found in server: " + id)
        }
        root.discardNotification(id);
    }

    function getNotificationById(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        return index !== -1 ? root.list[index] : null;
    }

    function resolveDesktopEntryForNotif(notif) {
        if (!notif) return null;

        const candidates = [];
        const desktopEntry = (notif.desktopEntry || "").trim();
        const appName = (notif.appName || "").trim();

        if (desktopEntry.length > 0) {
            candidates.push(desktopEntry);
            candidates.push(desktopEntry.replace(/\.desktop$/i, ""));
        }
        if (appName.length > 0) {
            candidates.push(appName);
        }

        for (let i = 0; i < candidates.length; i++) {
            const id = candidates[i];
            if (!id || id.length === 0) continue;

            const byId = DesktopEntries.byId(id);
            if (byId) return byId;

            const heuristic = DesktopEntries.heuristicLookup(id);
            if (heuristic) return heuristic;
        }

        return null;
    }

    function canOpenNotificationSourceApp(id) {
        const notif = getNotificationById(id);
        return resolveDesktopEntryForNotif(notif) !== null;
    }

    function openNotificationSourceApp(id) {
        const notif = getNotificationById(id);
        const entry = resolveDesktopEntryForNotif(notif);
        if (!entry) return false;
        return AppLaunch.launchDesktopEntry(entry);
    }

    function triggerListChange() {
        root.list = root.list.slice(0)
    }

    function refresh() {
        notifFileView.reload()
    }

    Component.onCompleted: {
        refresh()
    }

    FileView {
        id: notifFileView
        path: Qt.resolvedUrl(filePath)
        onLoaded: {
            const fileContents = notifFileView.text()
            root.list = JSON.parse(fileContents).map((notif) => {
                return notifComponent.createObject(root, {
                    "notificationId": notif.notificationId,
                    "actions": [], // Notification actions are meaningless if they're not tracked by the server or the sender is dead
                    "desktopEntry": notif.desktopEntry ?? "",
                    "appIcon": notif.appIcon,
                    "appName": notif.appName,
                    "body": notif.body,
                    "image": notif.image,
                    "summary": notif.summary,
                    "time": notif.time,
                    "urgency": notif.urgency,
                });
            });
            // Find largest notificationId
            let maxId = 0
            root.list.forEach((notif) => {
                maxId = Math.max(maxId, notif.notificationId)
            })

            console.log("[Notifications] File loaded")
            root.idOffset = maxId
            root.initDone()
        }
        onLoadFailed: (error) => {
            if(error == FileViewError.FileNotFound) {
                console.log("[Notifications] File not found, creating new file.")
                root.list = []
                notifFileView.setText(stringifyList(root.list));
            } else {
                console.log("[Notifications] Error loading file: " + error)
            }
        }
    }
}
