pragma Singleton

import QtQuick
import qs.modules.common

QtObject {
    id: root

    readonly property int connectivity: SettingsCatalog.indexOf("connectivity")
    readonly property int peripherals: SettingsCatalog.indexOf("peripherals")
    readonly property int display: SettingsCatalog.indexOf("display")
    readonly property int audio: SettingsCatalog.indexOf("audio")
    readonly property int notifications: SettingsCatalog.indexOf("notifications")
    readonly property int personalisation: SettingsCatalog.indexOf("personalisation")
    readonly property int apps: SettingsCatalog.indexOf("apps")
    readonly property int accounts: SettingsCatalog.indexOf("accounts")
    readonly property int language: SettingsCatalog.indexOf("language")
    readonly property int accessibility: SettingsCatalog.indexOf("accessibility")
    readonly property int privacy: SettingsCatalog.indexOf("privacy")
    readonly property int system: SettingsCatalog.indexOf("system")
    readonly property int gaming: SettingsCatalog.indexOf("gaming")
    readonly property int services: SettingsCatalog.indexOf("services")
    readonly property int hyprland: SettingsCatalog.indexOf("hyprland")

    readonly property var entries: [
        { label: "Wi-Fi networks", page: root.connectivity, subTab: 0, sectionId: "networks", icon: "wifi" },
        { label: "Scan Wi-Fi", page: root.connectivity, subTab: 0, sectionId: "networks", icon: "wifi_find" },
        { label: "Ethernet", page: root.connectivity, subTab: 0, sectionId: "internet", icon: "lan" },
        { label: "Captive portal", page: root.connectivity, subTab: 0, sectionId: "extra", icon: "captive_portal" },
        { label: "Bluetooth adapter", page: root.connectivity, subTab: 1, sectionId: "adapter", icon: "settings_bluetooth" },
        { label: "Bluetooth devices", page: root.connectivity, subTab: 1, sectionId: "devices", icon: "bluetooth" },
        { label: "Pair Bluetooth device", page: root.connectivity, subTab: 1, sectionId: "devices", icon: "add_link" },
        { label: "Trusted Bluetooth device", page: root.connectivity, subTab: 1, sectionId: "devices", icon: "verified_user" },
        { label: "Bluetooth discoverable", page: root.connectivity, subTab: 1, sectionId: "adapter", icon: "visibility" },
        { label: "Sharing", page: root.connectivity, subTab: 2, icon: "share" },
        { label: "Remote access SSH", page: root.connectivity, subTab: 2, icon: "terminal" },

        { label: "Detected input devices", page: root.peripherals, subTab: 0, icon: "devices" },
        { label: "Mouse sensitivity", page: root.peripherals, subTab: 1, icon: "mouse" },
        { label: "Mouse acceleration profile", page: root.peripherals, subTab: 1, icon: "speed" },
        { label: "Mouse wheel speed", page: root.peripherals, subTab: 1, icon: "mouse" },
        { label: "Follow mouse focus", page: root.peripherals, subTab: 1, icon: "near_me" },
        { label: "Left-handed mouse", page: root.peripherals, subTab: 1, icon: "mouse" },
        { label: "Touchpad natural scroll", page: root.peripherals, subTab: 1, icon: "touchpad_mouse" },
        { label: "Tap to click", page: root.peripherals, subTab: 1, icon: "touchpad_mouse" },
        { label: "Disable touchpad while typing", page: root.peripherals, subTab: 1, icon: "keyboard_off" },
        { label: "Quickshell scroll tuning", page: root.peripherals, subTab: 1, icon: "tune" },
        { label: "Keyboard numlock", page: root.peripherals, subTab: 2, icon: "keyboard" },
        { label: "MechLands M75 keyboard", page: root.peripherals, subTab: 3, icon: "keyboard" },
        { label: "Logitech G502 mouse", page: root.peripherals, subTab: 3, icon: "mouse" },

        { label: "Monitor arrangement", page: root.display, subTab: 0, icon: "desktop_windows" },
        { label: "Monitor scale and rotation", page: root.display, subTab: 0, icon: "display_settings" },
        { label: "Brightness", page: root.display, subTab: 0, icon: "brightness_6" },
        { label: "Night light", page: root.display, subTab: 1, icon: "routine" },
        { label: "Colour temperature", page: root.display, subTab: 1, icon: "thermostat" },
        { label: "Anti-flashbang", page: root.display, subTab: 1, icon: "flare" },
        { label: "Power profile", page: root.display, subTab: 2, icon: "energy_savings_leaf" },
        { label: "Battery health", page: root.display, subTab: 2, icon: "battery_android_full" },
        { label: "Automatic suspend on low battery", page: root.display, subTab: 2, icon: "bedtime" },

        { label: "Default output device", page: root.audio, subTab: 0, icon: "speaker" },
        { label: "Application audio streams", page: root.audio, subTab: 0, icon: "apps" },
        { label: "Mono output", page: root.audio, subTab: 0, icon: "hearing" },
        { label: "Default input device", page: root.audio, subTab: 1, icon: "mic" },
        { label: "Microphone input", page: root.audio, subTab: 1, icon: "mic" },
        { label: "Earbang protection", page: root.audio, subTab: 2, icon: "hearing" },
        { label: "Volume ceiling", page: root.audio, subTab: 2, icon: "volume_down" },
        { label: "System sounds", page: root.audio, subTab: 2, icon: "notification_sound" },

        { label: "Do not disturb", page: root.notifications, subTab: 0, icon: "notifications_off" },
        { label: "Notification history", page: root.notifications, subTab: 1, icon: "history" },
        { label: "Notification timeout", page: root.notifications, subTab: 0, icon: "timer" },
        { label: "Focus mode", page: root.notifications, subTab: 2, icon: "center_focus_strong" },
        { label: "Presentation mode", page: root.notifications, subTab: 2, icon: "co_present" },
        { label: "Notification sounds", page: root.notifications, subTab: 0, icon: "music_note" },

        { label: "Wallpaper and colours", page: root.personalisation, subTab: 1, icon: "palette" },
        { label: "Dark mode", page: root.personalisation, subTab: 1, icon: "dark_mode" },
        { label: "GTK app theme", page: root.personalisation, subTab: 1, icon: "palette" },
        { label: "Qt and KDE app theme", page: root.personalisation, subTab: 1, icon: "palette" },
        { label: "Fonts", page: root.personalisation, subTab: 0, icon: "font_download" },
        { label: "Bar position and style", page: root.personalisation, subTab: 0, icon: "toolbar" },
        { label: "Dock", page: root.personalisation, subTab: 0, icon: "dock" },
        { label: "Sidebars", page: root.personalisation, subTab: 0, icon: "side_navigation" },
        { label: "Lock screen", page: root.personalisation, subTab: 0, icon: "lock" },
        { label: "Overview layout", page: root.personalisation, subTab: 0, icon: "preview" },
        { label: "On-screen display", page: root.personalisation, subTab: 0, icon: "picture_in_picture" },

        { label: "Default browser", page: root.apps, subTab: 0, icon: "public" },
        { label: "Default mail app", page: root.apps, subTab: 0, icon: "mail" },
        { label: "Default file manager", page: root.apps, subTab: 0, icon: "folder" },
        { label: "Startup apps", page: root.apps, subTab: 1, icon: "rocket_launch" },
        { label: "Installed applications", page: root.apps, subTab: 0, icon: "apps" },

        { label: "Profile", page: root.accounts, subTab: 0, icon: "account_circle" },
        { label: "QuickMail accounts", page: root.accounts, subTab: 1, icon: "alternate_email" },
        { label: "Internet accounts", page: root.accounts, subTab: 1, icon: "hub" },
        { label: "Change password", page: root.accounts, subTab: 2, icon: "password" },
        { label: "Users", page: root.accounts, subTab: 2, icon: "group" },

        { label: "Clock format 24h 12h", page: root.language, subTab: 0, icon: "schedule" },
        { label: "Second precision clock", page: root.language, subTab: 0, icon: "pace" },
        { label: "Time zone", page: root.language, subTab: 0, icon: "globe" },
        { label: "Automatic network time NTP", page: root.language, subTab: 0, icon: "sync" },
        { label: "Language and locale", page: root.language, subTab: 1, icon: "language" },
        { label: "Translation map", page: root.language, subTab: 2, icon: "translate" },
        { label: "Locale JSON editor", page: root.language, subTab: 2, icon: "code" },

        { label: "Text scale", page: root.accessibility, subTab: 0, icon: "format_size" },
        { label: "Higher contrast", page: root.accessibility, subTab: 0, icon: "contrast" },
        { label: "Reduce transparency", page: root.accessibility, subTab: 0, icon: "opacity" },
        { label: "Cursor size", page: root.accessibility, subTab: 0, icon: "mouse" },
        { label: "Reduce motion", page: root.accessibility, subTab: 1, icon: "motion_photos_off" },
        { label: "Live captions", page: root.accessibility, subTab: 2, icon: "subtitles" },
        { label: "On-screen keyboard", page: root.accessibility, subTab: 2, icon: "keyboard" },

        { label: "AI privacy policy", page: root.privacy, subTab: 0, icon: "policy" },
        { label: "Clipboard privacy", page: root.privacy, subTab: 0, icon: "assignment" },
        { label: "Sandbox app permissions", page: root.privacy, subTab: 1, icon: "app_badging" },
        { label: "Secure Boot", page: root.privacy, subTab: 2, icon: "verified_user" },
        { label: "Disk encryption", page: root.privacy, subTab: 2, icon: "encrypted" },

        { label: "System information", page: root.system, subTab: 0, icon: "info" },
        { label: "Computer name and hostname", page: root.system, subTab: 0, icon: "dns" },
        { label: "CPU memory GPU", page: root.system, subTab: 0, icon: "memory" },
        { label: "Storage and disks", page: root.system, subTab: 1, icon: "hard_drive" },
        { label: "Check for updates", page: root.system, subTab: 2, icon: "system_update" },
        { label: "System diagnostics", page: root.system, subTab: 3, icon: "monitor_heart" },
        { label: "Logs", page: root.system, subTab: 3, icon: "description" },

        { label: "Game mode", page: root.gaming, subTab: 0, icon: "sports_esports" },
        { label: "Performance profile", page: root.gaming, subTab: 1, icon: "speed" },
        { label: "Gaming overlays", page: root.gaming, subTab: 2, icon: "monitoring" },
        { label: "Game controllers", page: root.peripherals, subTab: 0, icon: "gamepad" },

        { label: "AI system prompt", page: root.services, subTab: 0, icon: "neurology" },
        { label: "Search engine and prefixes", page: root.services, subTab: 0, icon: "search" },
        { label: "Music recognition", page: root.services, subTab: 1, icon: "music_cast" },
        { label: "Weather", page: root.services, subTab: 1, icon: "weather_mix" },
        { label: "User agent", page: root.services, subTab: 1, icon: "cell_tower" },
        { label: "Screenshot and recording paths", page: root.services, subTab: 2, icon: "file_open" },
        { label: "Resource polling", page: root.services, subTab: 2, icon: "memory" },

        { label: "Hyprland config files", page: root.hyprland, subTab: 0, icon: "deployed_code" },
        { label: "Keybinds", page: root.hyprland, subTab: 1, icon: "keyboard" },
        { label: "Window rules", page: root.hyprland, subTab: 2, icon: "select_window" },
        { label: "Workspace bindings", page: root.hyprland, subTab: 1, icon: "workspaces" },
        { label: "Monitor overrides", page: root.hyprland, subTab: 2, icon: "display_settings" },
        { label: "Environment variables", page: root.hyprland, subTab: 0, icon: "variables" },
        { label: "Startup commands", page: root.hyprland, subTab: 3, icon: "rocket_launch" }
    ]
}
