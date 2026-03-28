#!/usr/bin/env python3
import json
import re
import subprocess

try:
    import dbus
    _DBUS_OK = True
except ImportError:
    _DBUS_OK = False


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


def get_notifications_dbus(device_id):
    """Query active notifications via DBus, returning structured objects."""
    rc, out, _ = run([
        "qdbus", "org.kde.kdeconnect",
        f"/modules/kdeconnect/devices/{device_id}/notifications",
        "org.kde.kdeconnect.device.notifications.activeNotifications",
    ])
    if rc != 0 or not out.strip():
        return []

    notif_ids = [line.strip() for line in out.splitlines() if line.strip()]
    iface = "org.kde.kdeconnect.device.notifications.notification"
    result = []
    for notif_id in notif_ids[:8]:
        path = f"/modules/kdeconnect/devices/{device_id}/notifications/{notif_id}"
        props = {}
        for prop in ["appName", "title", "text", "ticker", "hasIcon", "iconPath"]:
            rc_p, val, _ = run(["qdbus", "org.kde.kdeconnect", path, f"{iface}.{prop}"])
            props[prop] = val.strip() if rc_p == 0 else ""

        app_name = props.get("appName", "")
        ticker = props.get("ticker", "")
        if not app_name and not ticker:
            continue

        result.append({
            "appName": app_name,
            "title": props.get("title", ""),
            "text": props.get("text", ""),
            "ticker": ticker,
            "iconPath": props.get("iconPath", ""),
        })
    return result


def get_sms_conversations(device_id):
    """Query SMS conversations via DBus activeConversations(), sorted by timestamp desc."""
    if not _DBUS_OK:
        return []
    try:
        bus = dbus.SessionBus()
        obj = bus.get_object("org.kde.kdeconnect", f"/modules/kdeconnect/devices/{device_id}")
        iface = dbus.Interface(obj, "org.kde.kdeconnect.device.conversations")
        try:
            iface.requestAllConversations()
        except Exception:
            pass
        convs = iface.activeConversations()
    except Exception:
        return []

    def unpack(v):
        if isinstance(v, (list, tuple)) or hasattr(v, '__iter__') and not isinstance(v, (str, bytes)):
            try:
                return [unpack(i) for i in v]
            except Exception:
                return str(v)
        if hasattr(v, 'real'):  # dbus numeric types
            return int(v)
        return str(v)

    results = []
    for conv in convs:
        try:
            u = unpack(conv)
            # Signature: (isa(s)xiixixa(xsss))
            # 0=type, 1=body, 2=addresses, 3=timestamp_ms, 4=event, 5=read, 6=threadId, ...
            addresses = u[2] if len(u) > 2 else []
            contact = addresses[0][0] if addresses and addresses[0] else ""
            body = u[1] if len(u) > 1 else ""
            timestamp = u[3] if len(u) > 3 else 0
            read = bool(u[5]) if len(u) > 5 else True
            thread_id = u[6] if len(u) > 6 else 0
            msg_type = u[0] if len(u) > 0 else 0  # 1=received, 2=sent
            results.append({
                "contact": contact,
                "body": body,
                "timestamp": timestamp,
                "threadId": thread_id,
                "read": read,
                "sent": msg_type == 2,
            })
        except Exception:
            continue

    results.sort(key=lambda x: -(x["timestamp"] or 0))
    return results[:20]


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

        notifications = get_notifications_dbus(device_id)
        sms_conversations = get_sms_conversations(device_id) if device_id in available_ids else []

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

        devices.append({
            "id": device_id,
            "name": name,
            "available": device_id in available_ids,
            "notificationCount": len(notifications),
            "notifications": notifications,
            "battery": battery,
            "charging": charging,
            "remoteCommands": remote_commands,
            "mountPoint": mount_point,
            "smsConversations": sms_conversations,
        })

    print(json.dumps({"devices": devices, "error": ""}))


if __name__ == "__main__":
    main()
