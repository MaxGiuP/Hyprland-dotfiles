import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

// From https://github.com/caelestia-dots/shell with modifications.
// License: GPLv3

Image {
    id: root
    required property var fileModelData
    asynchronous: true
    fillMode: Image.PreserveAspectFit

    readonly property bool isDesktopFile: !fileModelData.fileIsDir && fileModelData.filePath.endsWith(".desktop")

    // Quick extension-based icon lookup — shown immediately, before any process runs.
    readonly property string initialFileIcon: {
        if (fileModelData.fileIsDir) return "";
        const parts = fileModelData.fileName.toLowerCase().split(".");
        const ext = parts.length > 1 ? parts[parts.length - 1] : "";
        const map = {
            // Scripts / source code
            "py":   "text-x-python",
            "js":   "text-x-javascript",
            "mjs":  "text-x-javascript",
            "cjs":  "text-x-javascript",
            "ts":   "text-x-typescript",
            "jsx":  "text-x-javascript",
            "tsx":  "text-x-typescript",
            "html": "text-html",
            "htm":  "text-html",
            "css":  "text-css",
            "scss": "text-css",
            "sh":   "application-x-shellscript",
            "bash": "application-x-shellscript",
            "zsh":  "application-x-shellscript",
            "fish": "application-x-shellscript",
            "rs":   "text-x-rust",
            "go":   "text-x-go",
            "c":    "text-x-c",
            "cpp":  "text-x-c++src",
            "cc":   "text-x-c++src",
            "h":    "text-x-chdr",
            "hpp":  "text-x-c++hdr",
            "java": "text-x-java",
            "rb":   "application-x-ruby",
            "php":  "application-x-php",
            "lua":  "text-x-lua",
            "r":    "text-x-r",
            "swift":"text-x-swift",
            "kt":   "text-x-kotlin",
            "cs":   "text-x-csharp",
            "vb":   "text-x-vbasic",
            // Data / config
            "json": "application-json",
            "yaml": "text-x-yaml",
            "yml":  "text-x-yaml",
            "xml":  "text-xml",
            "toml": "text-x-toml",
            "csv":  "text-csv",
            "sql":  "text-x-sql",
            "md":   "text-x-markdown",
            "rst":  "text-x-rst",
            "txt":  "text-plain",
            // Documents
            "pdf":  "application-pdf",
            "doc":  "application-msword",
            "docx": "application-vnd.openxmlformats-officedocument.wordprocessingml.document",
            "odt":  "application-vnd.oasis.opendocument.text",
            "xls":  "application-vnd.ms-excel",
            "xlsx": "application-vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "ods":  "application-vnd.oasis.opendocument.spreadsheet",
            "ppt":  "application-vnd.ms-powerpoint",
            "pptx": "application-vnd.openxmlformats-officedocument.presentationml.presentation",
            // Archives
            "zip":  "application-zip",
            "tar":  "application-x-tar",
            "gz":   "application-x-compressed-tar",
            "bz2":  "application-x-bzip-compressed-tar",
            "xz":   "application-x-xz-compressed-tar",
            "zst":  "application-zstd",
            "7z":   "application-x-7z-compressed",
            "rar":  "application-x-rar",
            // Audio
            "mp3":  "audio-x-mpeg",
            "ogg":  "audio-x-vorbis+ogg",
            "flac": "audio-x-flac",
            "wav":  "audio-x-wav",
            "aac":  "audio-aac",
            "m4a":  "audio-mp4",
            // Video
            "mp4":  "video-mp4",
            "mkv":  "video-x-matroska",
            "avi":  "video-x-msvideo",
            "mov":  "video-quicktime",
            "webm": "video-webm",
            "flv":  "video-x-flv",
            // Fonts
            "ttf":  "font-x-generic",
            "otf":  "font-x-generic",
            "woff": "font-x-generic",
            "woff2":"font-x-generic",
        };
        return map[ext] || "text-plain";
    }

    source: {
        if (!fileModelData.fileIsDir)
            return Quickshell.iconPath(initialFileIcon);

        if ([Directories.documents, Directories.downloads, Directories.music, Directories.pictures, Directories.videos].some(dir => FileUtils.trimFileProtocol(dir) === fileModelData.filePath))
            return Quickshell.iconPath(`folder-${fileModelData.fileName.toLowerCase()}`);

        return Quickshell.iconPath("inode-directory");
    }

    onStatusChanged: {
        if (status === Image.Error)
            source = Quickshell.iconPath("error");
    }

    // For .desktop files: read the Icon= field and use it directly
    Process {
        running: root.isDesktopFile
        command: ["grep", "-m1", "^Icon=", fileModelData.filePath]
        stdout: StdioCollector {
            onStreamFinished: {
                const line = text.trim();
                if (line.startsWith("Icon=")) {
                    const iconName = line.slice(5).trim();
                    if (iconName)
                        root.source = iconName.startsWith("/") ? ("file://" + iconName) : Quickshell.iconPath(iconName, "application-x-desktop");
                }
            }
        }
    }

    // For everything else: use xdg-mime for accurate MIME type (extension + magic bytes),
    // then map to the freedesktop icon name. Falls back to the extension-based icon.
    Process {
        running: !fileModelData.fileIsDir && !root.isDesktopFile
        command: ["xdg-mime", "query", "filetype", fileModelData.filePath]
        stdout: StdioCollector {
            onStreamFinished: {
                const mime = text.trim();
                if (!mime) return;
                const iconName = mime.replace("/", "-");
                root.source = Images.validImageTypes.some(t => mime === `image/${t}`)
                    ? fileModelData.fileUrl
                    : Quickshell.iconPath(iconName, root.initialFileIcon);
            }
        }
    }
}
