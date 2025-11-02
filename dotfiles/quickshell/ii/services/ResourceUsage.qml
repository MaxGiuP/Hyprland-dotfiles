pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services 1.0

/**
 * Resource service con RAM/Swap e CPU.
 * Raggruppa i core in Performance vs Efficient con configurazione esplicita.
 */
Singleton {
    // Memoria
    property double memoryTotal: 1
    property double memoryFree: 1
    property double memoryUsed: memoryTotal - memoryFree
    property double memoryUsedPercentage: memoryUsed / memoryTotal
    property double swapTotal: 1
    property double swapFree: 1
    property double swapUsed: swapTotal - swapFree
    property double swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0

    // CPU aggregata
    property double cpuUsage: 0
    property int cpuUsagePercent: Math.round(cpuUsage * 100)
    property var previousCpuStats

    // Config raggruppamento (scegline uno)
    property var effIndices: []          // es. [16,17,18,19,20,21,22,23,24,25,26,27]
    property int effSuffixCount: 12      // default per il tuo layout; metti 0 per disattivare
    property int freqSplitKHz: 0         // es. 4500000 per ≤4.5 GHz = E

    // Gruppi risolti
    property var perfCores: []
    property var effCores: []
    property bool groupsReady: false
    property int logicalCpuCount: 0

    // Utilizzi di gruppo
    property double perfUsage: 0
    property int perfUsagePercent: Math.round(perfUsage * 100)
    property double effUsage: 0
    property int effUsagePercent: Math.round(effUsage * 100)

    // Stato per differenze per-core
    property var perCorePrev: []   // { total, idle }

    FileView { id: fileMeminfo; path: "/proc/meminfo" }
    FileView { id: fileStat; path: "/proc/stat" }
    FileView { id: sysFile; path: "" }

    function readText(p) {
        sysFile.path = p
        sysFile.reload()
        return sysFile.text()
    }
    function readCoreMaxFreq(c) {
        // kHz, 0 se non disponibile
        let n = Number(readText(`/sys/devices/system/cpu/cpu${c}/cpufreq/cpuinfo_max_freq`))
        if (!Number.isFinite(n) || n <= 0)
            n = Number(readText(`/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_max_freq`))
        return Number.isFinite(n) ? n : 0
    }

    function buildGroups(totalCpus) {
        // 1) Indici espliciti
        if (effIndices && effIndices.length > 0) {
            const effSet = {}
            for (let i = 0; i < effIndices.length; i++) effSet[effIndices[i]] = true
            const perf = []
            const eff = []
            for (let c = 0; c < totalCpus; c++) {
                if (effSet[c]) eff.push(c); else perf.push(c)
            }
            perfCores = perf; effCores = eff; groupsReady = true; return
        }

        // 2) Suffisso ultimi N core
        if (effSuffixCount > 0) {
            const perf = []
            const eff = []
            const startEff = Math.max(0, totalCpus - effSuffixCount)
            for (let c = 0; c < totalCpus; c++) {
                if (c >= startEff) eff.push(c); else perf.push(c)
            }
            perfCores = perf; effCores = eff; groupsReady = true; return
        }

        // 3) Soglia frequenza
        if (freqSplitKHz > 0) {
            const perf = []
            const eff = []
            for (let c = 0; c < totalCpus; c++) {
                const f = readCoreMaxFreq(c)
                if (f > 0 && f <= freqSplitKHz) eff.push(c); else perf.push(c)
            }
            perfCores = perf; effCores = eff; groupsReady = true; return
        }

        // Fallback: tutto Performance
        perfCores = Array.from({ length: totalCpus }, (_, i) => i)
        effCores = []
        groupsReady = true
    }

    Timer {
        interval: 1
        running: true
        repeat: true
        onTriggered: {
            // Memoria
            fileMeminfo.reload()
            const tmem = fileMeminfo.text()
            memoryTotal = Number(tmem.match(/MemTotal:\s*(\d+)/)?.[1] ?? 1)
            memoryFree  = Number(tmem.match(/MemAvailable:\s*(\d+)/)?.[1] ?? 0)
            swapTotal   = Number(tmem.match(/SwapTotal:\s*(\d+)/)?.[1] ?? 1)
            swapFree    = Number(tmem.match(/SwapFree:\s*(\d+)/)?.[1] ?? 0)

            // CPU total
            fileStat.reload()
            const textStat = fileStat.text()
            const head = textStat.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/m)
            if (head) {
                const a = head.slice(1).map(Number)
                const total = a.reduce((x, y) => x + y, 0)
                const idle  = a[3]
                if (previousCpuStats) {
                    const td = total - previousCpuStats.total
                    const id = idle  - previousCpuStats.idle
                    cpuUsage = td > 0 ? 1 - id / td : 0
                    cpuUsagePercent = Math.round(cpuUsage * 100)
                }
                previousCpuStats = { total, idle }
            }

            // Per-core differenze per questo tick
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
                const idle  = arr[3]   // se vuoi considerare iowait come idle, usa arr[3] + arr[4]
                const prev  = perCorePrev[core]
                let td = 0, id = 0
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

            // Accumula per gruppi usando i diff catturati sopra
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

            perfUsage = pTD > 0 ? 1 - pID / pTD : 0
            effUsage  = eTD > 0 ? 1 - eID / eTD : 0
            perfUsagePercent = Math.round(perfUsage * 100)
            effUsagePercent  = Math.round(effUsage  * 100)

            // Commit prev e intervallo
            perCorePrev = nextPrev
            interval = Config.options?.resources?.updateInterval ?? 3000
        }
    }
}
