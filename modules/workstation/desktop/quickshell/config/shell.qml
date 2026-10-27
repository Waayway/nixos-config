//@ pragma UseQApplication
// Quickshell: the bar, notifications and the power menu, all on the primary
// monitor (services/Primary.qml). ~/.config/quickshell is a link to this folder
// (quickshell_home.nix); Quickshell reloads on save.
import Quickshell
import qs.bar
import qs.notifications
import qs.services
import qs.session

ShellRoot {
    // One set of windows per primary screen. When the primary changes or its
    // screen goes away (undocking), the windows are destroyed and made again
    // on the new one, instead of being left behind on a screen that's gone.
    Variants {
        model: Primary.screen ? [Primary.screen] : []

        Scope {
            id: scope
            required property ShellScreen modelData

            Bar {
                screen: scope.modelData
            }
            Popups {
                screen: scope.modelData
            }
            Panel {
                screen: scope.modelData
            }
            PowerMenu {
                screen: scope.modelData
            }
        }
    }
}
