pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * Simple to-do list manager.
 * Each item is an object with "content" and "done" properties.
 */
Singleton {
    id: root
    property var filePath: Directories.todoPath
    property var list: []
    
    function pad2(n) { n = Math.max(0, Math.min(99, Math.round(n))); return ("0"+n).slice(-2); }

    // Convert "DD-MM-YYYY" -> "YYYY-MM-DD"; returns null if invalid
    function isoFromDDMM(ddmmyyyy) {
        const m = /^(\d{2})-(\d{2})-(\d{4})$/.exec(String(ddmmyyyy||""));
        if (!m) return null;
        const d  = parseInt(m[1],10), mo = parseInt(m[2],10), y = parseInt(m[3],10);
        if (mo < 1 || mo > 12) return null;
        const dim = [31, (y%4===0 && (y%100!==0 || y%400===0))?29:28, 31,30,31,30,31,31,30,31,30,31][mo-1];
        if (d < 1 || d > dim) return null;
        return m[3] + "-" + pad2(m[2]) + "-" + pad2(m[1]);
    }

    // Normalize "HH:MM" (or "H", "H:M", etc) -> "HH:MM"; returns null if invalid
    function normalizeTime(hhmm) {
        if (hhmm == null) return null;
        const s = String(hhmm);
        const parts = s.split(":");
        let h = parseInt(parts[0]||"0", 10);
        let m = parseInt((parts.length > 1 ? parts[1] : "0"), 10);
        if (isNaN(h) || isNaN(m)) return null;
        if (h < 0 || h > 23) return null;
        if (m < 0 || m > 59) return null;
        return pad2(h) + ":" + pad2(m);
    }

    function addItem(item) {
        list.push(item)
        // Reassign to trigger onListChanged
        root.list = list.slice(0)
        todoFileView.setText(JSON.stringify(root.list))
    }

    function addTask(desc, date, time) {
        const item = {
            "content": desc,
            "date": date,
            "time": time,
            "done": false,
        }
        addItem(item)
    }

    function markDone(index) {
        if (index >= 0 && index < list.length) {
            Quickshell.execDetached([
                "sh","-lc",
                "kitty --hold bash -lc 'echo " + String(index) + "; exec bash'"
            ]);
            // 0 = events, 1 = tasks
            const flag = "--complete-index"

            const py  = "python3";
            const mut = "/home/linmax/.config/quickshell/ii/modules/sidebarRight/todo/bb_mutate.py";
            const db  = "/home/linmax/.thunderbird/343n4iu7.default-default/calendar-data/local.sqlite";
            Quickshell.execDetached([
                "sh","-lc",
                "kitty --hold bash -lc 'echo " + py + " " + mut + " --db " + db + " " + flag + " " + index + " --force" + "; exec bash'"
            ]);
            // run synchronously so we know if it worked
            Quickshell.execDetached([
                "kitty", "--hold", "python3", mut, "--db", db, flag, index, "--force"
            ]);

            list[index].done = true
            // Reassign to trigger onListChanged
            root.list = list.slice(0)
            todoFileView.setText(JSON.stringify(root.list))
        }
    }

    function markUnfinished(index) {
        if (index >= 0 && index < list.length) {
            Quickshell.execDetached([
                "sh","-lc",
                "kitty --hold bash -lc 'echo " + String(index) + "; exec bash'"
            ]);
            // 0 = events, 1 = tasks
            const flag = "--uncomplete-index"

            const py  = "python3";
            const mut = "/home/linmax/.config/quickshell/ii/modules/sidebarRight/todo/bb_mutate.py";
            const db  = "/home/linmax/.thunderbird/343n4iu7.default-default/calendar-data/local.sqlite";
            Quickshell.execDetached([
                "sh","-lc",
                "kitty --hold bash -lc 'echo " + py + " " + mut + " --db " + db + " " + flag + " " + index + " --force" + "; exec bash'"
            ]);
            // run synchronously so we know if it worked
            Quickshell.execDetached([
                "kitty", "--hold", "python3", mut, "--db", db, flag, index, "--force"
            ]);

            list[index].done = false
            // Reassign to trigger onListChanged
            root.list = list.slice(0)
            todoFileView.setText(JSON.stringify(root.list))
        }
    }

    function deleteItem(index, tab) {
        if (index < 0) return;
        Quickshell.execDetached([
            "sh","-lc",
            "kitty --hold bash -lc 'echo " + String(index) + "; exec bash'"
        ]);
        // 0 = events, 1 = tasks
        const flag = (tab === 0) ? "--delete-event-index" : "--delete-index";

        const py  = "python3";
        const mut = "/home/linmax/.config/quickshell/ii/modules/sidebarRight/todo/bb_mutate.py";
        const db  = "/home/linmax/.thunderbird/343n4iu7.default-default/calendar-data/local.sqlite";
        Quickshell.execDetached([
            "sh","-lc",
            "kitty --hold bash -lc 'echo " + py + " " + mut + " --db " + db + " " + flag + " " + index + " --force" + "; exec bash'"
        ]);
        // run synchronously so we know if it worked
        Quickshell.execDetached([
            "kitty", "--hold", "python3", mut, "--db", db, flag, index, "--force"
        ]);
        

        list.splice(index, 1);
        root.list = list.slice(0);
        todoFileView.setText(JSON.stringify(root.list));
    }

    function refresh() {
        todoFileView.reload()
    }

    Component.onCompleted: {
        refresh()
    }

    FileView {
        id: todoFileView
        path: Qt.resolvedUrl(root.filePath)
        onLoaded: {
            const fileContents = todoFileView.text()
            root.list = JSON.parse(fileContents)
            console.log("[To Do] File loaded")
        }
        onLoadFailed: (error) => {
            if(error == FileViewError.FileNotFound) {
                console.log("[To Do] File not found, creating new file.")
                root.list = []
                todoFileView.setText(JSON.stringify(root.list))
            } else {
                console.log("[To Do] Error loading file: " + error)
            }
        }
    }
}

