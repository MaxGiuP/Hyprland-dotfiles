pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * Simple to-do list manager.
 * Each item is an object with "title", "description" and "done" properties.
 */
Singleton {
    id: root
    property var filePath: Directories.todoPath
    property var list: []
    
    function normalizeItem(item) {
        const title = `${item?.title ?? item?.content ?? ""}`.trim();
        const description = `${item?.description ?? ""}`.trim();
        return {
            "title": title,
            "description": description,
            "content": title,
            "done": !!item?.done,
            "dueAt": 0,
            "createdAt": Math.max(0, parseInt(item?.createdAt ?? Date.now()) || Date.now()),
            "source": "local",
        };
    }
    
    function addItem(item) {
        const normalized = normalizeItem(item);
        if (normalized.title.length === 0) return;
        list.push(normalized)
        // Reassign to trigger onListChanged
        root.list = list.slice(0)
        todoFileView.setText(JSON.stringify(root.list))
    }

    function addTask(title, description = "") {
        const item = {
            "title": title,
            "description": description,
            "done": false,
            "createdAt": Date.now(),
            "source": "local",
        }
        addItem(item)
    }

    function markDone(index) {
        if (index >= 0 && index < list.length) {
            list[index].done = true
            // Reassign to trigger onListChanged
            root.list = list.slice(0)
            todoFileView.setText(JSON.stringify(root.list))
        }
    }

    function markUnfinished(index) {
        if (index >= 0 && index < list.length) {
            list[index].done = false
            // Reassign to trigger onListChanged
            root.list = list.slice(0)
            todoFileView.setText(JSON.stringify(root.list))
        }
    }

    function deleteItem(index) {
        if (index >= 0 && index < list.length) {
            list.splice(index, 1)
            // Reassign to trigger onListChanged
            root.list = list.slice(0)
            todoFileView.setText(JSON.stringify(root.list))
        }
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
            const parsed = JSON.parse(fileContents)
            root.list = Array.isArray(parsed) ? parsed.map(item => root.normalizeItem(item)).filter(item => item.title.length > 0) : []
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
