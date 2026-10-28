.pragma library

var LEVELS = [
  { depth: 1, name: "Tidy",     root: false, detail: "Trims 20% of your session's file cache. No password, nothing slows down." },
  { depth: 2, name: "Light",    root: false, detail: "Reclaims 10% of idle session memory, compressing cold pages into zram." },
  { depth: 3, name: "Standard", root: true,  detail: "Light, plus drops the kernel page, dentry and inode caches." },
  { depth: 4, name: "Deep",     root: true,  detail: "Reclaims 25% of session memory, drops all caches and compacts RAM." },
  { depth: 5, name: "Max",      root: true,  detail: "Reclaims 50% of session and 25% of services memory, drops caches, compacts. Apps may stutter briefly while pages return." }
]

function parseMeminfo(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^(\w+(?:\(\w+\))?):\s+(\d+)/)
    if (m) out[m[1]] = parseInt(m[2], 10)
  }
  var total = out.MemTotal || 0
  var avail = out.MemAvailable || 0
  var cache = (out.Cached || 0) + (out.Buffers || 0) + (out.SReclaimable || 0) - (out.Shmem || 0)
  return {
    valid: total > 0,
    totalKiB: total,
    availableKiB: avail,
    freeKiB: out.MemFree || 0,
    usedKiB: Math.max(0, total - avail),
    cacheKiB: Math.max(0, cache),
    swapTotalKiB: out.SwapTotal || 0,
    swapUsedKiB: Math.max(0, (out.SwapTotal || 0) - (out.SwapFree || 0)),
    usedFraction: total > 0 ? Math.max(0, Math.min(1, (total - avail) / total)) : 0,
    cacheFraction: total > 0 ? Math.max(0, Math.min(1, cache / total)) : 0,
    swapFraction: out.SwapTotal > 0 ? Math.max(0, Math.min(1, (out.SwapTotal - out.SwapFree) / out.SwapTotal)) : 0
  }
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
  if (!r.ok) return r.error === "already running" ? "Already running" : ("Failed: " + (r.error || "unknown error"))
  var freed = Math.max(r.freedKiB || 0, r.availableDeltaKiB || 0)
  var secs = ((r.ms || 0) / 1000).toFixed(1)
  return "Freed " + formatKiB(freed) + " in " + secs + " s"
}

function helperNote(r) {
  if (!r || !r.ok) return ""
  if (r.helper === "missing") return "Root helper not installed, so kernel caches were kept."
  if (r.helper === "denied") return "Root step was cancelled, so kernel caches were kept."
  return ""
}
