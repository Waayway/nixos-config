pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Screen-share picker state. xdg-desktop-portal-hyprland runs the picker program named in
// ~/.config/hypr/xdph.conf (custom_picker_binary = quickshell-share-picker, from
// quickshell_home.nix); that script opens this over IPC and waits for the answer:
//   qs ipc call sharepicker open <XDPH_WINDOW_SHARING_LIST> <allowToken> <resultPath>
// The answer is written to resultPath: "[r]/screen:<connector>" or "[r]/window:<id>",
// "r" meaning the app may restore the choice without asking again; empty means cancelled.
Singleton {
    id: root

    property bool open: false
    property bool allowToken: true
    property string resultPath: ""
    // [{ id, cls, title, address }] from the portal's window list.
    property var windows: []

    // XDPH's list: "<id>[HC>]<class>[HT>]<title>[HE>]<hyprland address>[HA>]" per window.
    // The address is a decimal number; Hyprland's IPC uses hex.
    function parse(list) {
        const out = [];
        for (const entry of list.split("[HA>]")) {
            const c = entry.indexOf("[HC>]");
            const t = entry.indexOf("[HT>]");
            const e = entry.indexOf("[HE>]");
            if (c < 0 || t < 0 || e < 0)
                continue;
            const dec = entry.slice(e + 5);
            out.push({
                id: entry.slice(0, c),
                cls: entry.slice(c + 5, t),
                title: entry.slice(t + 5, e),
                address: /^[0-9]+$/.test(dec) ? Number(dec).toString(16) : ""
            });
        }
        return out;
    }

    // The Wayland toplevel for a window, for its live preview. Called from a binding, so it
    // updates when Hyprland's toplevel list does (refreshToplevels() is asynchronous).
    function toplevelFor(address) {
        if (!address)
            return null;
        for (const t of Hyprland.toplevels.values) {
            if (t.address.replace(/^0x/, "").toLowerCase() === address)
                return t.wayland;
        }
        return null;
    }

    function finish(selection) {
        if (!open)
            return;
        open = false;
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" > \"$2.tmp\" && mv \"$2.tmp\" \"$2\"", "sh", selection, resultPath]);
    }

    function chooseScreen(name) {
        finish((allowToken ? "r" : "") + "/screen:" + name);
    }

    function chooseWindow(id) {
        finish((allowToken ? "r" : "") + "/window:" + id);
    }

    function cancel() {
        finish("");
    }

    IpcHandler {
        target: "sharepicker"

        function open(list: string, allowToken: bool, resultPath: string): void {
            // A new request replaces one still open; the old one is answered "cancelled".
            root.cancel();
            Hyprland.refreshToplevels();
            root.windows = root.parse(list);
            root.allowToken = allowToken;
            root.resultPath = resultPath;
            root.open = true;
        }
        function close(): void {
            root.cancel();
        }
    }
}
