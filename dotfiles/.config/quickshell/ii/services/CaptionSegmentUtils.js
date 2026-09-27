.pragma library

// A pair is valid only after that source sentence has its own completed
// translation. Never infer alignment from two independently split paragraphs.
function sanitizeSegments(payload, maximumSegments) {
    const input = Array.isArray(payload) ? payload : payload?.translation_segments
    if (!Array.isArray(input))
        return []

    const limit = Math.max(1, Math.min(32, Math.floor(maximumSegments || 12)))
    const result = []
    const seen = new Set()
    for (let index = input.length - 1; index >= 0 && result.length < limit; index--) {
        const item = input[index]
        if (!item || typeof item !== "object" || Array.isArray(item)
                || typeof item.id !== "string" || typeof item.source !== "string")
            continue
        const id = item.id.trim()
        const source = item.source.trim()
        if (!id || !source || seen.has(id))
            continue
        seen.add(id)
        const translated = typeof item.translated === "string" ? item.translated.trim() : ""
        const pending = item.pending !== false || translated.length === 0
        // Older workers have no separator and retain their sentence-per-line layout.
        const separator = item.separator === " " || item.separator === "" ? item.separator : "\n"
        result.push({ id, source, translated: pending ? "" : translated, pending, separator })
    }
    return result.reverse()
}

function escapeRichText(text) {
    return String(text ?? "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;")
        .replace(/\r\n?|\n/g, "<br>")
}

function colorIndex(id, colorCount) {
    // Backend IDs end with a monotonic sequence number. Cycling by that number
    // cycles through the palette without changing colours when older phrases
    // scroll out of view.
    const numericSuffix = String(id).match(/(\d+)$/)
    if (numericSuffix) {
        const number = Number(numericSuffix[1])
        if (Number.isSafeInteger(number))
            return number % colorCount
    }
    let hash = 2166136261
    for (let index = 0; index < String(id).length; index++)
        hash = Math.imul(hash ^ String(id).charCodeAt(index), 16777619)
    return (hash >>> 0) % colorCount
}

function colorChannels(color) {
    let hex = String(color).replace(/^#/, "")
    // QColor strings use #aarrggbb when an alpha component is present.
    if (hex.length === 8)
        hex = hex.slice(2)
    if (!/^[0-9a-f]{6}$/i.test(hex))
        return [0, 0, 0]
    return [0, 2, 4].map(offset => parseInt(hex.slice(offset, offset + 2), 16) / 255)
}

function channelsHex(channels) {
    return "#" + channels.map(value => Math.round(Math.max(0, Math.min(1, value)) * 255)
        .toString(16).padStart(2, "0")).join("")
}

function luminance(color) {
    const channels = colorChannels(color).map(value => value <= 0.04045
        ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4))
    return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
}

function contrastRatio(foreground, background) {
    const first = luminance(foreground)
    const second = luminance(background)
    return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05)
}

function contrastAdjustedColor(candidate, background, minimumContrast) {
    if (contrastRatio(candidate, background) >= minimumContrast)
        return candidate

    const blackRatio = contrastRatio("#000000", background)
    const whiteRatio = contrastRatio("#ffffff", background)
    const destination = blackRatio >= whiteRatio ? 0 : 1
    const fallback = destination === 0 ? "#000000" : "#ffffff"
    if (contrastRatio(fallback, background) < minimumContrast)
        return fallback // Best available contrast on unusually mid-tone themes.

    const channels = colorChannels(candidate)
    let lower = 0
    let upper = 1
    let result = fallback
    for (let step = 0; step < 12; step++) {
        const mix = (lower + upper) / 2
        const adjusted = channelsHex(channels.map(value => value + (destination - value) * mix))
        if (contrastRatio(adjusted, background) >= minimumContrast) {
            result = adjusted
            upper = mix
        } else {
            lower = mix
        }
    }
    return result
}

function colorForId(id, palette, background, minimumContrast) {
    return contrastAdjustedColor(palette[colorIndex(id, palette.length)], background, minimumContrast)
}

function markup(segments, translated, palette, background, neutralColor, minimumContrast) {
    const neutral = contrastAdjustedColor(neutralColor, background, minimumContrast)
    const lines = []
    let lineBreak = false
    for (const segment of segments) {
        lineBreak = lineBreak || segment.separator !== " " && segment.separator !== ""
        const completed = !segment.pending && segment.translated.length > 0
        if (translated && !completed)
            continue
        const color = completed ? colorForId(segment.id, palette, background, minimumContrast) : neutral
        const text = translated ? segment.translated : segment.source
        const separator = lines.length ? (lineBreak ? "<br>" : " ") : ""
        lines.push(`${separator}<span style="color:${color};">${escapeRichText(text)}</span>`)
        lineBreak = false
    }
    return lines.join("")
}

function plainText(segments, translated) {
    const parts = []
    let lineBreak = false
    for (const segment of segments) {
        lineBreak = lineBreak || segment.separator !== " " && segment.separator !== ""
        if (translated && (segment.pending || !segment.translated.length))
            continue
        const separator = parts.length ? (lineBreak ? "\n" : " ") : ""
        parts.push(separator + (translated ? segment.translated : segment.source))
        lineBreak = false
    }
    return parts.join("")
}
