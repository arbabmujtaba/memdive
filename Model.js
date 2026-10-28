.pragma library

var LEVELS = [
  { depth: 1, name: "Surface", root: false, detail: "Trims 20% of your session's file cache. Instant, no password, nothing slows down." },
  { depth: 2, name: "Shallow", root: false, detail: "Reclaims 10% of idle session memory. Cold pages move to compressed swap." },
  { depth: 3, name: "Reef",    root: true,  detail: "Shallow, plus drops the kernel page, dentry and inode caches." },
  { depth: 4, name: "Deep",    root: true,  detail: "Reclaims 25% of session memory, drops all caches and compacts RAM." },
  { depth: 5, name: "Abyss",   root: true,  detail: "Reclaims 50% of session and 25% of services memory, drops caches, compacts. Apps may stutter while pages return." }
]

function levelName(depth) {
  var l = LEVELS[(Number(depth) || 1) - 1]
  return l ? l.name : "?"
}

function parseMeminfo(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^(\w+(?:\(\w+\))?):\s+(\d+)/)
    if (m) out[m[1]] = parseInt(m[2], 10)
  }
  var total = out.MemTotal || 0
  var avail = out.MemAvailable !== undefined ? out.MemAvailable : (out.MemFree || 0) + (out.Cached || 0)
  var cache = (out.Cached || 0) + (out.Buffers || 0) + (out.SReclaimable || 0) - (out.Shmem || 0)
  var swapTotal = out.SwapTotal || 0
  var swapUsed = Math.max(0, swapTotal - (out.SwapFree || 0))
  function frac(v, of) { return of > 0 ? Math.max(0, Math.min(1, v / of)) : 0 }
  return {
    valid: total > 0,
    totalKiB: total,
    availableKiB: avail,
    usedKiB: Math.max(0, total - avail),
    cacheKiB: Math.max(0, cache),
    swapTotalKiB: swapTotal,
    swapUsedKiB: swapUsed,
    usedFraction: frac(total - avail, total),
    cacheFraction: frac(cache, total),
    swapFraction: frac(swapUsed, swapTotal)
  }
}

function parseCaps(text) {
  try {
    var c = JSON.parse(String(text || "").trim())
    if (c && typeof c === "object") return c
  } catch (e) {}
  return null
}

function formatKiB(kib) {
  var v = Number(kib) || 0
  if (v >= 1024 * 1024) return (v / 1024 / 1024).toFixed(v >= 10 * 1024 * 1024 ? 1 : 2) + " GB"
  if (v >= 1024) return Math.round(v / 1024) + " MB"
  return Math.round(v) + " KB"
}

function percent(fraction) {
  return Math.round((Number(fraction) || 0) * 100) + "%"
}

function resultText(r) {
  if (!r) return ""
  if (!r.ok) return r.error === "already running" ? "Already diving" : ("Failed: " + (r.error || "unknown error"))
  var freed = Math.max(r.freedKiB || 0, r.availableDeltaKiB || 0, r.sessionReclaimedKiB || 0)
  return "Freed " + formatKiB(freed) + " in " + ((r.ms || 0) / 1000).toFixed(1) + " s"
}

// Same result, phrased for the handwritten dive log.
function resultNote(r) {
  if (!r) return ""
  if (!r.ok) return r.error === "already running" ? "already diving, hang on" : ("that dive failed: " + (r.error || "unknown error"))
  var freed = Math.max(r.freedKiB || 0, r.availableDeltaKiB || 0, r.sessionReclaimedKiB || 0)
  return "freed " + formatKiB(freed) + " in " + ((r.ms || 0) / 1000).toFixed(1) + " s"
}

function helperNote(r) {
  if (!r || !r.ok) return ""
  if (r.helper === "missing") return "root helper isn't installed, so kernel caches stayed put"
  if (r.helper === "outdated") return "root helper is out of date, so kernel caches stayed put"
  if (r.helper === "denied") return "root step was cancelled, so kernel caches stayed put"
  if (r.helper === "nopkexec") return "pkexec isn't available, so kernel caches stayed put"
  return ""
}

// history.jsonl -> { recent: [...newest first], todayCount, todayKiB }
function parseHistory(text, nowMs) {
  var lines = String(text || "").split("\n")
  var entries = []
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i]) continue
    try {
      var e = JSON.parse(lines[i])
      if (e && e.t && e.level) entries.push(e)
    } catch (err) {}
  }
  var start = new Date(nowMs)
  start.setHours(0, 0, 0, 0)
  var since = start.getTime() / 1000
  var count = 0, kib = 0
  for (var j = 0; j < entries.length; j++) {
    if (entries[j].t >= since) { count++; kib += entries[j].freedKiB || 0 }
  }
  return { recent: entries.slice(-4).reverse(), todayCount: count, todayKiB: kib }
}

function logLine(e, nowMs) {
  var d = new Date(e.t * 1000)
  var today = new Date(nowMs)
  var sameDay = d.toDateString() === today.toDateString()
  var when = sameDay ? Qt.formatTime(d, "HH:mm") : Qt.formatDate(d, "d MMM")
  return { when: when, name: levelName(e.level).toLowerCase(), depth: e.level, freed: "+" + formatKiB(e.freedKiB || 0) }
}

// One handwritten hint for the notes card, picked from what matters most now.
function tip(mem, caps, focusDepth) {
  if (caps && caps.helper !== "installed" && (focusDepth >= 3 || caps.reclaim === false))
    return caps.helper === "outdated"
      ? "the root helper is out of date. reinstall it below and depths 3-5 work again"
      : "depths 3-5 need a tiny root helper. install it once below, no password after that"
  if (caps && caps.reclaim === false)
    return "this kernel can't reclaim per-app memory, so every depth goes through the root helper"
  if (mem.swapTotalKiB === 0 && focusDepth >= 2)
    return "no swap on this machine, so only cache can be freed. zram would help a lot"
  if (mem.usedFraction >= 0.85) return "pressure is high! Deep (4) should buy real room"
  if (mem.usedFraction >= 0.65) return "getting crowded. Shallow or Reef is a good dive"
  if (mem.usedFraction < 0.4) return "plenty of air up here. Surface is all you need"
  return "freed cache refills as you open files. that's normal, not a leak"
}
