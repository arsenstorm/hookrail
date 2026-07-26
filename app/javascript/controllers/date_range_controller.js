import { Controller } from "@hotwired/stimulus"

// The custom half of the time-range split control: a month grid plus start/end
// date and time fields and a Local/UTC choice. Everything is resolved in the
// browser; on submit the picks are composed into ISO datetimes (offset
// included) in the hidden from/to fields, so the server never has to guess
// the visitor's timezone.
export default class extends Controller {
  static targets = ["grid", "monthLabel", "startDate", "startTime", "endDate", "endTime",
                    "fromField", "toField", "tz"]
  static values = { from: String, to: String }

  connect() {
    const from = this.hydrate(this.fromValue)
    const to = this.hydrate(this.toValue)
    this.start = from.day || null
    this.end = to.day || null
    this.startTimeTarget.value = from.time || ""
    this.endTimeTarget.value = to.time || ""
    const anchor = this.start || new Date()
    this.month = new Date(anchor.getFullYear(), anchor.getMonth(), 1)
    this.tzTarget.options[0].text = `Local (${Intl.DateTimeFormat().resolvedOptions().timeZone})`
    this.syncInputs()
    this.render()
  }

  // "2026-07-26" or "2026-07-26T14:52:00+01:00" -> local day + wall-clock time.
  hydrate(value) {
    if (!value) return {}
    const date = new Date(value.length === 10 ? `${value}T00:00` : value)
    if (isNaN(date)) return {}
    return {
      day: new Date(date.getFullYear(), date.getMonth(), date.getDate()),
      time: value.includes(":") ? `${this.pad(date.getHours())}:${this.pad(date.getMinutes())}` : null
    }
  }

  render() {
    this.monthLabelTarget.textContent =
      this.month.toLocaleDateString("en-US", { month: "long", year: "numeric" })
    const lead = (this.month.getDay() + 6) % 7 // Monday-first grid
    const daysInMonth = new Date(this.month.getFullYear(), this.month.getMonth() + 1, 0).getDate()
    const cellCount = Math.ceil((lead + daysInMonth) / 7) * 7
    const cursor = new Date(this.month)
    cursor.setDate(1 - lead)
    const cells = []
    for (let i = 0; i < cellCount; i++) {
      cells.push(this.cell(new Date(cursor)))
      cursor.setDate(cursor.getDate() + 1)
    }
    this.gridTarget.replaceChildren(...cells)
  }

  cell(date) {
    const button = document.createElement("button")
    button.type = "button"
    button.textContent = date.getDate()
    button.dataset.action = "date-range#pick"
    button.dataset.date = this.iso(date)
    button.setAttribute("aria-label", date.toDateString())
    const picked = this.same(date, this.start) || this.same(date, this.end)
    const between = this.start && this.end && date > this.start && date < this.end
    const inMonth = date.getMonth() === this.month.getMonth()
    button.className = "size-9 cursor-pointer rounded-md text-sm tabular-nums " + (
      picked ? "bg-neutral-950 font-medium text-white dark:bg-white dark:text-neutral-950"
      : between ? "bg-neutral-950/5 text-neutral-950 dark:bg-white/10 dark:text-white"
      : inMonth ? "text-neutral-700 hover:bg-neutral-950/5 dark:text-neutral-300 dark:hover:bg-white/5"
      : "text-neutral-400 hover:bg-neutral-950/5 dark:text-neutral-600 dark:hover:bg-white/5")
    return button
  }

  pick(event) {
    const date = new Date(`${event.target.dataset.date}T00:00`)
    if (!this.start || this.end) {
      this.start = date
      this.end = null
    } else if (date < this.start) {
      this.start = date
    } else {
      this.end = date
    }
    this.syncInputs()
    this.render()
  }

  prev() { this.shift(-1) }
  next() { this.shift(1) }

  shift(delta) {
    this.month = new Date(this.month.getFullYear(), this.month.getMonth() + delta, 1)
    this.render()
  }

  // A date typed into the Start/End field; anything unparseable is reverted.
  dateChanged(event) {
    const typed = new Date(event.target.value)
    if (isNaN(typed)) {
      this.syncInputs()
      return
    }
    const day = new Date(typed.getFullYear(), typed.getMonth(), typed.getDate())
    if (event.params.bound === "start") this.start = day
    else this.end = day
    if (this.start && this.end && this.end < this.start) {
      [this.start, this.end] = [this.end, this.start]
    }
    this.month = new Date(day.getFullYear(), day.getMonth(), 1)
    this.syncInputs()
    this.render()
  }

  // Runs on form submit (Apply button or Enter in any field).
  compose() {
    const tz = this.tzTarget.value
    this.fromFieldTarget.value = this.stamp(this.start, this.time(this.startTimeTarget, "00:00"), tz)
    this.toFieldTarget.value = this.stamp(this.end || this.start, this.time(this.endTimeTarget, "23:59"), tz)
  }

  time(input, fallback) {
    const raw = input.value.trim()
    return /^\d{1,2}:\d{2}$/.test(raw) ? raw.padStart(5, "0") : fallback
  }

  stamp(day, time, tz) {
    if (!day) return ""
    const base = `${this.iso(day)}T${time}:00`
    if (tz === "utc") return `${base}Z`
    const offset = -new Date(base).getTimezoneOffset()
    const abs = Math.abs(offset)
    return `${base}${offset < 0 ? "-" : "+"}${this.pad(Math.floor(abs / 60))}:${this.pad(abs % 60)}`
  }

  syncInputs() {
    this.startDateTarget.value = this.display(this.start)
    this.endDateTarget.value = this.display(this.end)
  }

  display(day) {
    if (!day) return ""
    return day.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })
  }

  iso(date) {
    return `${date.getFullYear()}-${this.pad(date.getMonth() + 1)}-${this.pad(date.getDate())}`
  }

  same(a, b) { return b && a.getTime() === b.getTime() }
  pad(n) { return String(n).padStart(2, "0") }
}
