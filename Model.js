// Pure helpers for the Time Machine panel. Kept out of the QML so the JSON
// shape of `snapper --jsonout list` and the date/description formatting can be
// reasoned about (and unit-tested) without a shell.

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function asNumber(value) {
  var n = Number(value)
  return isFinite(n) ? n : 0
}

function isEmpty(value) {
  return value === undefined || value === null || String(value).trim() === ""
}

function parseEnvelope(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, error: "No response from the snapshot helper." }
  var data
  try {
    data = JSON.parse(text)
  } catch (e) {
    return { ok: false, error: text.split("\n")[0] }
  }
  if (!data || typeof data !== "object") return { ok: false, error: "Unreadable response from the snapshot helper." }
  return data
}

function normalizeSnapshot(entry) {
  var s = entry || {}
  var number = asNumber(s.number)
  var rawUserdata = s.userdata
  var userdata = ""
  var important = false

  if (rawUserdata && typeof rawUserdata === "object") {
    var parts = []
    for (var key in rawUserdata) {
      parts.push(key + "=" + rawUserdata[key])
      if (key === "important" && String(rawUserdata[key]).toLowerCase() === "yes") important = true
    }
    userdata = parts.join(",")
  } else if (rawUserdata !== undefined && rawUserdata !== null) {
    userdata = String(rawUserdata)
    important = /(^|[,;\s])important=yes([,;\s]|$)/.test(userdata)
  }

  return {
    number: number,
    preNumber: asNumber(s["pre-number"] !== undefined ? s["pre-number"]
      : (s.pre_number !== undefined ? s.pre_number : s.preNumber)),
    date: String(s.date === undefined || s.date === null ? "" : s.date),
    user: String(s.user === undefined || s.user === null ? "" : s.user),
    cleanup: String(s.cleanup === undefined || s.cleanup === null ? "" : s.cleanup),
    description: String(s.description === undefined || s.description === null ? "" : s.description),
    userdata: userdata,
    current: number === 0 || s.current === true,
    important: important
  }
}

function unwrapSnapshots(raw) {
  if (Array.isArray(raw)) return raw
  if (raw && typeof raw === "object") {
    // snapper --jsonout groups entries by config name: {"root":[...]}.
    if (Array.isArray(raw.root)) return raw.root
    for (var key in raw) if (Array.isArray(raw[key])) return raw[key]
  }
  return null
}

function parseSnapshotList(payload) {
  var envelope = typeof payload === "string" ? parseEnvelope(payload) : (payload || {})
  if (envelope.ok === false) {
    // Older helpers wrapped snapper's JSON in an error string. Accept that
    // shape so a stale installed helper still renders instead of dead-ending.
    var embedded = null
    if (typeof envelope.error === "string" && envelope.error.trim().charAt(0) === "{") {
      try { embedded = JSON.parse(envelope.error) } catch (e) { embedded = null }
    }
    if (embedded === null) {
      return { ok: false, error: String(envelope.error || "Could not read snapshots."), snapshots: [] }
    }
    envelope = { ok: true, snapshots: embedded }
  }
  var raw = unwrapSnapshots(envelope.snapshots)
  if (raw === null) {
    return { ok: false, error: "The snapshot list was not an array.", snapshots: [] }
  }
  var snapshots = []
  for (var i = 0; i < raw.length; i++) {
    if (!raw[i] || typeof raw[i] !== "object") continue
    snapshots.push(normalizeSnapshot(raw[i]))
  }
  // Newest first, but keep the "current" pseudo-snapshot pinned at the top.
  snapshots.sort(function(a, b) {
    if (a.current !== b.current) return a.current ? -1 : 1
    return b.number - a.number
  })
  return { ok: true, error: "", snapshots: snapshots }
}

function formatDate(raw) {
  var text = String(raw || "").trim()
  if (text === "") return "unknown time"
  var m = text.match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})/)
  if (!m) return text
  var month = MONTHS[Number(m[2]) - 1] || m[2]
  return month + " " + Number(m[3]) + " · " + m[4] + ":" + m[5]
}

function describe(snapshot) {
  var s = snapshot || {}
  if (s.current) return "Current system"
  if (!isEmpty(s.description)) return String(s.description)
  if (s.cleanup === "pre") return "Before update"
  if (s.cleanup === "post") return "After update"
  return "Snapshot " + s.number
}

function subtitle(snapshot) {
  var s = snapshot || {}
  if (s.current) return "running system"
  var parts = [formatDate(s.date)]
  if (s.important) parts.push("keep")
  return parts.join(" · ")
}

function defaultDescription(now) {
  var d = now instanceof Date ? now : new Date()
  var pad = function(n) { return (n < 10 ? "0" : "") + n }
  return "Manual " + d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
    + " " + pad(d.getHours()) + ":" + pad(d.getMinutes())
}

function parseBootSnapshot(fsroot) {
  var text = String(fsroot || "").trim()
  var m = text.match(/\.snapshots\/([0-9]+)\/snapshot/)
  return m ? Number(m[1]) : 0
}

function isAuthProblem(message) {
  return /password is required|not allowed|terminal is required|sudo:/i.test(String(message || ""))
}

function countSaved(snapshots) {
  var list = Array.isArray(snapshots) ? snapshots : []
  var n = 0
  for (var i = 0; i < list.length; i++) if (list[i] && !list[i].current) n++
  return n
}

if (typeof module !== "undefined") {
  module.exports = {
    parseEnvelope: parseEnvelope,
    parseSnapshotList: parseSnapshotList,
    normalizeSnapshot: normalizeSnapshot,
    unwrapSnapshots: unwrapSnapshots,
    formatDate: formatDate,
    describe: describe,
    subtitle: subtitle,
    defaultDescription: defaultDescription,
    parseBootSnapshot: parseBootSnapshot,
    isAuthProblem: isAuthProblem,
    countSaved: countSaved
  }
}
