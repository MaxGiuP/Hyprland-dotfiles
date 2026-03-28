#!/usr/bin/env python3
import json
import re
import subprocess


def run(cmd):
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=4)
        return proc.returncode, (proc.stdout or ""), (proc.stderr or "")
    except Exception as exc:
        return 1, "", str(exc)


def parse_id_name(output):
    result = []
    for line in output.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split(" ", 1)
        if len(parts) == 1:
            result.append({"id": parts[0], "name": parts[0]})
        else:
            result.append({"id": parts[0], "name": parts[1].strip()})
    return result


def parse_qvariant_int(text):
    match = re.search(r"(-?\d+)", text or "")
    return int(match.group(1)) if match else -1


def parse_qvariant_bool(text):
    lowered = (text or "").lower()
    return "true" in lowered


def dbus_prop(device_id, iface, prop):
    rc, out, err = run([
        "qdbus",
        "org.kde.kdeconnect",
        f"/modules/kdeconnect/devices/{device_id}/battery",
        "org.freedesktop.DBus.Properties.Get",
        iface,
        prop,
    ])
    return rc, out, err


def parse_notifications(out_text):
    lines = [line.strip() for line in out_text.splitlines() if line.strip()]
    return lines[:8]


def parse_remote_commands(out_text):
    commands = []
    for line in (out_text or "").splitlines():
        text = line.strip()
        if not text:
            continue
        if ":" in text:
            cmd_id, name = text.split(":", 1)
            commands.append({"id": cmd_id.strip(), "name": name.strip()})
        else:
            commands.append({"id": text, "name": text})
    return commands[:12]


def main():
    rc, list_out, list_err = run(["kdeconnect-cli", "--list-devices", "--id-name-only"])
    if rc != 0:
        print(json.dumps({"devices": [], "error": list_err.strip() or "kdeconnect-cli unavailable"}))
        return

    rc, avail_out, _ = run(["kdeconnect-cli", "--list-available", "--id-name-only"])
    available_ids = {entry["id"] for entry in parse_id_name(avail_out)} if rc == 0 else set()

    devices = []
    for entry in parse_id_name(list_out):
        device_id = entry["id"]
        name = entry["name"]

        rc_notif, notif_out, _ = run(["kdeconnect-cli", "--device", device_id, "--list-notifications"])
        notifications = parse_notifications(notif_out) if rc_notif == 0 else []
        rc_cmd, cmd_out, _ = run(["kdeconnect-cli", "--device", device_id, "--list-commands"])
        remote_commands = parse_remote_commands(cmd_out) if rc_cmd == 0 else []
        rc_mount, mount_out, _ = run(["kdeconnect-cli", "--device", device_id, "--get-mount-point"])
        mount_point = mount_out.strip() if rc_mount == 0 else ""

        battery = -1
        charging = False

        rc_bat, bat_out, _ = dbus_prop(device_id, "org.kde.kdeconnect.device.battery", "charge")
        if rc_bat == 0:
            battery = parse_qvariant_int(bat_out)

        rc_charge, charge_out, _ = dbus_prop(device_id, "org.kde.kdeconnect.device.battery", "isCharging")
        if rc_charge == 0:
            charging = parse_qvariant_bool(charge_out)

        devices.append(
            {
                "id": device_id,
                "name": name,
                "available": device_id in available_ids,
                "notificationCount": len(notifications),
                "notifications": notifications,
                "battery": battery,
                "charging": charging,
                "remoteCommands": remote_commands,
                "mountPoint": mount_point,
            }
        )

    print(json.dumps({"devices": devices, "error": ""}))


if __name__ == "__main__":
    main()
