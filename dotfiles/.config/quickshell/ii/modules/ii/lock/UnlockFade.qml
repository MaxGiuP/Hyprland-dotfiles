// Overlay approach abandoned: ext-session-lock-v1 pauses frame callbacks for
// layer-shell surfaces while the lock is active, so animations started before
// the lock releases never render. Workspace switching (in Lock.qml) handles
// the post-unlock transition instead.
import QtQuick
Item {}
