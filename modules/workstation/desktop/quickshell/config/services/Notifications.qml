pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Notification daemon (replaces swaync). Popups show on the primary monitor;
// everything stays in the history panel until dismissed.
//   qs ipc call notifications toggle | clear | dnd
Singleton {
    id: root

    property bool dnd: false
    property bool panelOpen: false

    // Every notification not yet dismissed.
    readonly property var history: server.trackedNotifications.values
    // The ones currently shown as popups (a subset of history).
    property var popups: []

    function hidePopup(n) {
        popups = popups.filter(p => p !== n);
    }

    function clear() {
        for (const n of [...history])
            n.dismiss();
        popups = [];
    }

    // Popup time in ms: the app's own when it sets one, otherwise 5 s low,
    // 10 s normal, sticky critical (swaync's old settings).
    function timeout(n) {
        if (n.urgency === NotificationUrgency.Critical)
            return 0;
        if (n.expireTimeout > 0)
            return n.expireTimeout;
        return n.urgency === NotificationUrgency.Low ? 5000 : 10000;
    }

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            n.closed.connect(() => root.hidePopup(n));
            if (!root.panelOpen && (!root.dnd || n.urgency === NotificationUrgency.Critical))
                root.popups = [...root.popups, n];
        }
    }

    IpcHandler {
        target: "notifications"

        function toggle(): void {
            root.panelOpen = !root.panelOpen;
            if (root.panelOpen)
                root.popups = [];
        }
        function clear(): void {
            root.clear();
        }
        function dnd(): void {
            root.dnd = !root.dnd;
        }
    }
}
