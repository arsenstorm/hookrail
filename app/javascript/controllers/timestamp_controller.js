import { Controller } from "@hotwired/stimulus"

// The client half of the one timestamp convention. The server already rendered
// a correct value, so this only does what a server can't: rewrite the >=24h
// absolute date into the viewer's zone, keep recent values ticking, and build
// the hover card that spells the moment out in UTC and locally.
//
// The interval and the tooltip node are shared by the whole page. A table can
// hold a hundred of these, and a hundred timers or a hundred hidden popovers
// would be a hundred too many.

const MINUTE = 60
const HOUR = 3600
const DAY = 86400

// ---- shared ticker -----------------------------------------------------

const live = new Set()
let ticker = null

function watch(controller) {
  live.add(controller)
  ticker ||= setInterval(() => live.forEach((c) => c.render()), 10000)
}

// Dropped once a value reaches its absolute date: it will never change again,
// so the last element to settle also stops the clock.
function unwatch(controller) {
  live.delete(controller)
  if (live.size === 0 && ticker) {
    clearInterval(ticker)
    ticker = null
  }
}

// ---- shared tooltip ----------------------------------------------------

// popover="manual" puts the card in the top layer, which is the whole reason
// it's used here: several of these tables live inside an overflow-x-auto
// scroller that would otherwise clip an absolutely positioned tooltip.
let tip = null
let shown = null

function tooltip() {
  if (tip) return tip
  tip = document.createElement("div")
  tip.id = "timestamp-tooltip"
  tip.setAttribute("role", "tooltip")
  tip.setAttribute("popover", "manual")
  tip.className =
    "elevated pointer-events-none m-0 w-max rounded-lg p-3 text-xs whitespace-nowrap"
  tip.style.position = "fixed"
  tip.style.inset = "auto"
  document.body.append(tip)
  return tip
}

const GAP = 8

function place(host) {
  const anchor = host.getBoundingClientRect()
  const card = tip.getBoundingClientRect()
  // Flip above when there isn't room below, and clamp sideways so a timestamp
  // in the last column can't push the card off screen.
  const below = anchor.bottom + GAP + card.height <= window.innerHeight
  const top = below ? anchor.bottom + GAP : anchor.top - card.height - GAP
  const centred = anchor.left + anchor.width / 2 - card.width / 2
  const left = Math.min(Math.max(GAP, centred), window.innerWidth - card.width - GAP)
  tip.style.top = `${Math.max(GAP, top)}px`
  tip.style.left = `${Math.max(GAP, left)}px`
}

// ---- formatting --------------------------------------------------------

const DATE_OPTS = { month: "short", day: "numeric", year: "numeric" }
const TIME_OPTS = { hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false }

function format(date, opts, timeZone) {
  return new Intl.DateTimeFormat(undefined, timeZone ? { ...opts, timeZone } : opts).format(date)
}

function zoneName(date, timeZone) {
  const opts = { timeZoneName: "short", ...(timeZone ? { timeZone } : {}) }
  return new Intl.DateTimeFormat(undefined, opts)
    .formatToParts(date)
    .find((part) => part.type === "timeZoneName").value
}

// "2 days, 22 hours, 35 minutes ago" — three units is as much as anyone reads.
const UNITS = [["day", DAY], ["hour", HOUR], ["minute", MINUTE], ["second", 1]]

function humanDuration(date) {
  let rest = Math.round((Date.now() - date) / 1000)
  if (rest < 1) return "Just now"
  const parts = []
  for (const [name, size] of UNITS) {
    const n = Math.floor(rest / size)
    rest -= n * size
    if (n) parts.push(`${n} ${name}${n === 1 ? "" : "s"}`)
  }
  return `${parts.slice(0, 3).join(", ")} ago`
}

const CHIP =
  "rounded bg-neutral-950/5 px-1.5 py-0.5 text-[10px] font-medium text-neutral-600 dark:bg-white/10 dark:text-neutral-300"

function row(label, date, timeZone) {
  return `<span class="${CHIP}">${label}</span>` +
    `<span class="text-neutral-600 dark:text-neutral-400">${format(date, DATE_OPTS, timeZone)}</span>` +
    `<span class="text-right font-mono tabular-nums text-neutral-950 dark:text-white">${format(date, TIME_OPTS, timeZone)}</span>`
}

function card(date) {
  return `<p class="font-medium text-neutral-950 dark:text-white">${humanDuration(date)}</p>` +
    `<div class="mt-2 grid grid-cols-[auto_1fr_auto] items-center gap-x-3 gap-y-1">` +
    row("UTC", date, "UTC") + row(zoneName(date), date, undefined) +
    `</div>`
}

// ---- controller --------------------------------------------------------

export default class extends Controller {
  connect() {
    this.date = new Date(this.element.dateTime)
    // The element may sit inside a link that is already the tab stop; hang the
    // hover and focus behaviour off whatever the user actually reaches.
    this.host = this.element.closest("a[href], button") || this.element

    this.onShow = () => this.show()
    this.onHide = () => this.hide()
    this.onEscape = (event) => { if (event.key === "Escape") this.hide() }

    this.host.addEventListener("mouseenter", this.onShow)
    this.host.addEventListener("mouseleave", this.onHide)
    this.host.addEventListener("focus", this.onShow)
    this.host.addEventListener("blur", this.onHide)

    this.render()
  }

  disconnect() {
    this.hide()
    unwatch(this)
    this.host.removeEventListener("mouseenter", this.onShow)
    this.host.removeEventListener("mouseleave", this.onHide)
    this.host.removeEventListener("focus", this.onShow)
    this.host.removeEventListener("blur", this.onHide)
  }

  render() {
    const seconds = (Date.now() - this.date) / 1000
    this.element.textContent = this.label(seconds)
    if (seconds >= DAY) unwatch(this)
    else watch(this)
  }

  label(seconds) {
    if (seconds < 1) return "Just now"
    if (seconds < MINUTE) return `${Math.floor(seconds)}s ago`
    if (seconds < HOUR) return `${Math.floor(seconds / MINUTE)}m ago`
    if (seconds < DAY) return `${Math.floor(seconds / HOUR)}h ago`
    const opts = { month: "short", day: "numeric" }
    if (this.date.getFullYear() !== new Date().getFullYear()) opts.year = "numeric"
    return format(this.date, opts)
  }

  show() {
    // One card serves the page, so whoever had it must let go first.
    shown?.hide()
    // Built on first hover, not for every row on page load.
    const el = tooltip()
    if (!el.showPopover) return // no top layer, no tooltip — the text still reads fine
    el.innerHTML = card(this.date)
    el.showPopover()
    place(this.host)
    this.host.setAttribute("aria-describedby", el.id)
    document.addEventListener("keydown", this.onEscape)
    shown = this
  }

  hide() {
    if (shown !== this) return
    shown = null
    tip.hidePopover()
    this.host.removeAttribute("aria-describedby")
    document.removeEventListener("keydown", this.onEscape)
  }
}
