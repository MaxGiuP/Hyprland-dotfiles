-- Keep phone-remote cursor motion independent from physical mouse settings.
-- The application applies its own explicit movement scale before using ydotool.
hl.device({
    name = "ydotoold-virtual-device-1",
    accel_profile = "flat",
    sensitivity = 0,
})
