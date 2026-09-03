pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs.services

QtObject {
    readonly property list<var> pages: [
        { id: "home", displayName: Translation.tr("Home"), description: Translation.tr("Overview and shortcuts"), icon: "home", component: "modules/settings/HomeConfig.qml" },
        { id: "connectivity", displayName: Translation.tr("Network & connectivity"), description: Translation.tr("Wi-Fi, Ethernet, Bluetooth and sharing"), icon: "language", component: "modules/settings/ConnectivityConfig.qml" },
        { id: "peripherals", displayName: Translation.tr("Devices & input"), description: Translation.tr("Mouse, touchpad, keyboard and hardware"), icon: "devices", component: "modules/settings/PeripheralsConfig.qml" },
        { id: "display", displayName: Translation.tr("Displays & power"), description: Translation.tr("Monitors, colour, brightness and energy"), icon: "desktop_windows", component: "modules/settings/DisplayPowerConfig.qml" },
        { id: "audio", displayName: Translation.tr("Sound"), description: Translation.tr("Output, input, applications and safety"), icon: "volume_up", component: "modules/settings/AudioControlConfig.qml" },
        { id: "notifications", displayName: Translation.tr("Notifications & focus"), description: Translation.tr("Alerts, quiet modes and schedules"), icon: "notifications", component: "modules/settings/NotificationsFocusConfig.qml" },
        { id: "personalisation", displayName: Translation.tr("Personalisation"), description: Translation.tr("Theme, wallpaper and interface"), icon: "palette", component: "modules/settings/PersonalisationConfig.qml" },
        { id: "apps", displayName: Translation.tr("Apps & defaults"), description: Translation.tr("Default handlers, startup and installed apps"), icon: "apps", component: "modules/settings/AppsDefaultsConfig.qml" },
        { id: "accounts", displayName: Translation.tr("Accounts"), description: Translation.tr("Profile, online accounts and sign-in"), icon: "person", component: "modules/settings/AccountsConfig.qml" },
        { id: "language", displayName: Translation.tr("Time & language"), description: Translation.tr("Date, region, input and translation"), icon: "schedule", component: "modules/settings/DateTimeLanguageConfig.qml" },
        { id: "accessibility", displayName: Translation.tr("Accessibility"), description: Translation.tr("Vision, motion, hearing and input"), icon: "accessibility_new", component: "modules/settings/AccessibilityConfig.qml" },
        { id: "privacy", displayName: Translation.tr("Privacy & security"), description: Translation.tr("Policies, permissions and device security"), icon: "shield_lock", component: "modules/settings/PrivacySecurityConfig.qml" },
        { id: "system", displayName: Translation.tr("System"), description: Translation.tr("About, storage, updates and diagnostics"), icon: "computer", component: "modules/settings/SystemInfoUpdateConfig.qml" },
        { id: "gaming", displayName: Translation.tr("Gaming"), description: Translation.tr("Performance, overlays and controllers"), icon: "sports_esports", component: "modules/settings/GamingConfig.qml" },
        { id: "services", displayName: Translation.tr("Services"), description: Translation.tr("Search, integrations and data paths"), icon: "widgets", component: "modules/settings/ServicesConfig.qml" },
        { id: "hyprland", displayName: Translation.tr("Hyprland"), description: Translation.tr("Keybinds, rules and configuration"), icon: "deployed_code", component: "modules/settings/HyprConfig.qml" }
    ]

    function indexOf(pageId) {
        const index = pages.findIndex(page => page.id === pageId)
        return index < 0 ? 0 : index
    }
}
