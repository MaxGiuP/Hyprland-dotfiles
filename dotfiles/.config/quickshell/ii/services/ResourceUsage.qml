pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services 1.0

Singleton {
    id: root

    // Memory and swap (kB)
    property double memoryTotal: 1
    property double memoryFree: 0
    property double memoryUsed: Math.max(0, memoryTotal - memoryFree)
    property double memoryUsedPercentage: memoryTotal > 0 ? (memoryUsed / memoryTotal) : 0

    property double swapTotal: 1
    property double swapFree: 0
    property double swapUsed: Math.max(0, swapTotal - swapFree)
    property double swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0

    // CPU aggregate
    property double cpuUsage: 0
    property int cpuUsagePercent: Math.round(cpuUsage * 100)
    property var previousCpuStats

    // Max strings
    function kbToGbString(kb) { return (kb / (1024 * 1024)).toFixed(1) + " GB" }
    property string maxAvailableMemoryString: kbToGbString(memoryTotal)
    property string maxAvailableSwapString: kbToGbString(swapTotal)
    property string maxAvailableCpuString: "--"

    // Per-core grouping config
    property var effIndices: []
    property int effSuffixCount: 12
    property int freqSplitKHz: 0

    // Resolved groups
    property var perfCores: []
    property var effCores: []
    property bool groupsReady: false
    property int logicalCpuCount: 0

    // Group usages
    property double perfUsage: 0
    property int perfUsagePercent: Math.round(perfUsage * 100)
    property double effUsage: 0
    property int effUsagePercent: Math.round(effUsage * 100)

    // Per-core prev
    property var perCorePrev: []

    FileView { id: fileMeminfo; path: "/proc/meminfo" }
    FileView { id: fileStat; path: "/proc/stat" }
    FileView { id: sysFile; path: "" }

    function readText(p) {
        sysFile.path = p
        sysFile.reload()
        return sysFile.text()
    }

    function readCoreMaxFreq(c) {
        let n = Number(readText("/sys/devices/system/cpu/cpu" + c + "/cpufreq/cpuinfo_max_freq"))
        if (!Number.isFinite(n) || n <= 0)
            n = Number(readText("/sys/devices/system/cpu/cpu" + c + "/cpufreq/scaling_max_freq"))
        return Number.isFinite(n) ? n : 0
    }

    function buildGroups(totalCpus) {
        if (effIndices && effIndices.length > 0) {
            const effSet = {}
            for (let i = 0; i < effIndices.length; i++) effSet[effIndices[i]] = true
            const perf = []
            const eff = []
            for (let c = 0; c < totalCpus; c++) {
                if (effSet[c]) eff.push(c); else perf.push(c)
            }
            perfCores = perf
            effCores = eff
            groupsReady = true
            return
        }

        if (effSuffixCount > 0) {
            const perf = []
            const eff = []
            const startEff = Math.max(0, totalCpus - effSuffixCount)
            for (let c = 0; c < totalCpus; c++) {
                if (c >= startEff) eff.push(c); else perf.push(c)
            }
            perfCores = perf
            effCores = eff
            groupsReady = true
            return
        }

        if (freqSplitKHz > 0) {
            const perf = []
            const eff = []
            for (let c = 0; c < totalCpus; c++) {
                const f = readCoreMaxFreq(c)
                if (f > 0 && f <= freqSplitKHz) eff.push(c); else perf.push(c)
            }
            perfCores = perf
            effCores = eff
            groupsReady = true
            return
        }

        perfCores = Array.from({ length: totalCpus }, (_, i) => i)
        effCores = []
        groupsReady = true
    }

    Timer {
        interval: Math.max(100, Config.options?.resources?.updateInterval ?? 3000)
        running: true
        repeat: true
        onTriggered: {
            // Memory
            fileMeminfo.reload()
            const tmem = fileMeminfo.text() || ""
            const mt = Number(tmem.match(/MemTotal:\s*(\d+)/)?.[1] ?? 1)
            const ma = Number(tmem.match(/MemAvailable:\s*(\d+)/)?.[1] ?? 0)
            const st = Number(tmem.match(/SwapTotal:\s*(\d+)/)?.[1] ?? 1)
            const sf = Number(tmem.match(/SwapFree:\s*(\d+)/)?.[1] ?? 0)

            memoryTotal = (Number.isFinite(mt) && mt > 0) ? mt : 1
            memoryFree  = (Number.isFinite(ma) && ma >= 0) ? ma : 0
            swapTotal   = (Number.isFinite(st) && st >= 0) ? st : 0
            swapFree    = (Number.isFinite(sf) && sf >= 0) ? sf : 0

            // CPU
            fileStat.reload()
            const textStat = fileStat.text() || ""

            const head = textStat.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/m)
            if (head) {
                const a = head.slice(1).map(Number)
                const total = a.reduce((x, y) => x + y, 0)
                const idle  = a[3]
                if (previousCpuStats) {
                    const td = total - previousCpuStats.total
                    const id = idle  - previousCpuStats.idle
                    cpuUsage = td > 0 ? (1 - id / td) : 0
                    cpuUsagePercent = Math.round(cpuUsage * 100)
                }
                previousCpuStats = { total, idle }
            }

            const re = /^cpu(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/gm
            let m
            const nextPrev = perCorePrev.slice()
            const totalDiffs = []
            const idleDiffs  = []
            let maxCore = -1

            while ((m = re.exec(textStat)) !== null) {
                const core  = Number(m[1])
                if (core > maxCore) maxCore = core

                const arr = m.slice(2).map(Number)
                const total = arr.reduce((x, y) => x + y, 0)
                const idle  = arr[3]

                const prev = perCorePrev[core]
                let td = 0
                let id = 0
                if (prev) {
                    td = total - prev.total
                    id = idle  - prev.idle
                }

                totalDiffs[core] = td
                idleDiffs[core]  = id
                nextPrev[core] = { total, idle }
            }

            logicalCpuCount = maxCore + 1
            if (!groupsReady && logicalCpuCount > 0) {
                buildGroups(logicalCpuCount)
            }

            let pTD = 0, pID = 0, eTD = 0, eID = 0
            for (let i = 0; i < perfCores.length; i++) {
                const c = perfCores[i]
                pTD += totalDiffs[c] || 0
                pID += idleDiffs[c]  || 0
            }
            for (let i = 0; i < effCores.length; i++) {
                const c = effCores[i]
                eTD += totalDiffs[c] || 0
                eID += idleDiffs[c]  || 0
            }

            perfUsage = pTD > 0 ? (1 - pID / pTD) : 0
            effUsage  = eTD > 0 ? (1 - eID / eTD) : 0
            perfUsagePercent = Math.round(perfUsage * 100)
            effUsagePercent  = Math.round(effUsage * 100)

            perCorePrev = nextPrev
        }
    }

    Process {
        id: findCpuMaxFreqProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["bash", "-c", "lscpu | grep 'CPU max MHz' | awk '{print $4}'"]
        running: true
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                const mhz = parseFloat(outputCollector.text)
                if (Number.isFinite(mhz) && mhz > 0) {
                    root.maxAvailableCpuString = (mhz / 1000).toFixed(0) + " GHz"
                }
            }
        }
    }
}
