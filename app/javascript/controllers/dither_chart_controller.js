import { Controller } from "@hotwired/stimulus"

// Dithered canvas charts: an ordered Bayer 4x4 threshold matrix turns flat
// fills into a halftone dot texture — full density at the data line fading
// toward the baseline — instead of smooth gradients.
//
// Gridlines are always drawn behind the data; hovering adds a crosshair on the
// nearest bucket and a tooltip with that bucket's numbers.
//
//   data-dither-chart-type-value:   "area" | "bars"
//   data-dither-chart-labels-value: JSON array of bucket labels
//   data-dither-chart-series-value: JSON [{name, color, values: [Number]}]
//                                   area uses the first series; bars stack
//                                   the series bottom-up in the order given.
const BAYER = [
  [ 0,  8,  2, 10],
  [12,  4, 14,  6],
  [ 3, 11,  1,  9],
  [15,  7, 13,  5]
].map(row => row.map(v => (v + 0.5) / 16))

const DOT = 2 // tunable: logical px per dither cell — bigger = chunkier halftone
const GRID_LINES = 4 // tunable: horizontal gridlines behind the data

export default class extends Controller {
  static targets = ["canvas", "tooltip"]
  static values = { type: String, labels: Array, series: Array }

  connect() {
    this.index = null
    this.draw()
    // One redraw per frame: a resize drag fires far faster than we can redraw
    // two dithered canvases.
    this.resize = () => {
      if (this.frame) return
      this.frame = requestAnimationFrame(() => { this.frame = null; this.draw() })
    }
    addEventListener("resize", this.resize)
  }

  disconnect() {
    removeEventListener("resize", this.resize)
    if (this.frame) cancelAnimationFrame(this.frame)
  }

  // --- Interaction ---------------------------------------------------------

  hover(event) {
    const rect = this.canvasTarget.getBoundingClientRect()
    if (rect.width === 0) return

    const x = event.clientX - rect.left
    const index = this.indexAt(x, rect.width)
    if (index !== this.index) {
      this.index = index
      this.draw()
    }
    this.showTooltip(rect)
  }

  leave() {
    if (this.index === null) return
    this.index = null
    this.draw()
    this.tooltipTarget.hidden = true
  }

  indexAt(x, w) {
    const n = this.labelsValue.length
    if (n === 0) return null
    const t = this.typeValue === "bars" ? x / (w / n) : (x / w) * (n - 1)
    return Math.max(0, Math.min(n - 1, Math.round(this.typeValue === "bars" ? t - 0.5 : t)))
  }

  showTooltip(rect) {
    const tooltip = this.tooltipTarget
    const rows = this.seriesValue.map(s => [ s.color, s.name, s.values[this.index] || 0 ])
    const total = rows.reduce((sum, [ , , v ]) => sum + v, 0)

    tooltip.replaceChildren(this.tooltipMarkup(rows, rows.length > 1 ? total : null))
    tooltip.hidden = false

    // Clamp inside the chart so the tooltip never hangs off the card.
    const half = tooltip.offsetWidth / 2
    const x = this.xAt(this.index, rect.width)
    tooltip.style.left = `${Math.max(half, Math.min(rect.width - half, x))}px`
  }

  tooltipMarkup(rows, total) {
    const frag = document.createDocumentFragment()
    const label = document.createElement("p")
    label.className = "font-medium text-neutral-950 dark:text-white"
    label.textContent = this.labelsValue[this.index]
    frag.append(label)

    for (const [ color, name, value ] of rows) {
      const row = document.createElement("p")
      row.className = "mt-0.5 flex items-center gap-1.5 text-neutral-500 dark:text-neutral-400"
      const swatch = document.createElement("span")
      swatch.className = "inline-block size-2 shrink-0 rounded-xs"
      swatch.style.backgroundColor = color
      const text = document.createElement("span")
      text.textContent = `${name} ${value.toLocaleString()}`
      row.append(swatch, text)
      frag.append(row)
    }

    if (total !== null) {
      const sum = document.createElement("p")
      sum.className = "mt-0.5 text-neutral-500 dark:text-neutral-400"
      sum.textContent = `Total ${total.toLocaleString()}`
      frag.append(sum)
    }
    return frag
  }

  // --- Drawing -------------------------------------------------------------

  draw() {
    const canvas = this.canvasTarget
    const dpr = window.devicePixelRatio || 1
    const w = canvas.clientWidth
    const h = canvas.clientHeight
    if (w === 0 || this.seriesValue.length === 0) return
    canvas.width = w * dpr
    canvas.height = h * dpr
    const ctx = canvas.getContext("2d")
    ctx.scale(dpr, dpr)
    ctx.clearRect(0, 0, w, h)

    // Theme-aware line colors live in CSS so dark mode needs no JS branch.
    const styles = getComputedStyle(this.element)
    this.gridColor = styles.getPropertyValue("--chart-grid").trim()
    this.axisColor = styles.getPropertyValue("--chart-axis").trim()

    this.grid(ctx, w, h)
    if (this.typeValue === "bars") this.drawBars(ctx, w, h)
    else this.drawArea(ctx, w, h)
    if (this.index !== null) this.crosshair(ctx, w, h)
  }

  // Plot one dither cell if its intensity clears the Bayer threshold.
  dot(ctx, x, y, intensity) {
    if (intensity > BAYER[((y / DOT) | 0) % 4][((x / DOT) | 0) % 4]) ctx.fillRect(x, y, DOT, DOT)
  }

  // Shared y-scale: bars stack, area reads the single series.
  max() {
    const totals = this.labelsValue.map((_, i) =>
      this.seriesValue.reduce((sum, s) => sum + (s.values[i] || 0), 0))
    return Math.max(1, ...totals)
  }

  // Center of a bucket: bars own a slot, area points sit on the line.
  xAt(i, w) {
    const n = this.labelsValue.length
    if (this.typeValue === "bars") return (i + 0.5) * (w / n)
    return n < 2 ? 0 : i * (w - DOT) / (n - 1)
  }

  grid(ctx, w, h) {
    ctx.fillStyle = this.gridColor
    for (let i = 1; i <= GRID_LINES; i++) ctx.fillRect(0, Math.round(h - i * (h / GRID_LINES)), w, 1)
  }

  crosshair(ctx, w, h) {
    ctx.fillStyle = this.axisColor
    ctx.fillRect(Math.round(this.xAt(this.index, w)), 0, 1, h)
  }

  drawArea(ctx, w, h) {
    const series = this.seriesValue[0]
    const values = series.values
    const n = values.length
    if (n < 2) return
    const max = this.max()
    const pad = 4 // tunable
    const xAt = i => i * (w - DOT) / (n - 1)
    const yAt = v => pad + (1 - v / max) * (h - 2 * pad)

    ctx.fillStyle = series.color
    for (let x = 0; x < w; x += DOT) {
      const t = x / (w - DOT) * (n - 1)
      const i = Math.min(n - 2, t | 0)
      const yLine = yAt(values[i] + (values[i + 1] - values[i]) * (t - i))
      for (let y = Math.ceil(yLine / DOT) * DOT; y < h; y += DOT) {
        const fade = 1 - (y - yLine) / ((h - yLine) || 1)
        this.dot(ctx, x, y, 0.15 + 0.75 * fade) // tunable intensity range
      }
    }

    // Crisp line over the halftone fill.
    ctx.strokeStyle = series.color
    ctx.lineWidth = 1.5
    ctx.beginPath()
    values.forEach((v, i) => {
      if (i === 0) ctx.moveTo(xAt(i), yAt(v))
      else ctx.lineTo(xAt(i), yAt(v))
    })
    ctx.stroke()

    if (this.index === null) return

    // Marker on the hovered point, punched out of the fill so it stays legible.
    const x = xAt(this.index)
    const y = yAt(values[this.index])
    ctx.fillStyle = getComputedStyle(this.element).getPropertyValue("--surface").trim() || "#fff"
    ctx.beginPath()
    ctx.arc(x, y, 3.5, 0, Math.PI * 2)
    ctx.fill()
    ctx.stroke()
  }

  // Baseline the bars sit on — the area chart gets one for free from its own
  // fill, bars would otherwise float with no x axis.
  axis(ctx, w, h) {
    ctx.fillStyle = this.axisColor
    ctx.fillRect(0, h - 1, w, 1)
  }

  drawBars(ctx, w, h) {
    const n = this.labelsValue.length
    if (n === 0) return
    this.axis(ctx, w, h)
    const max = this.max()
    const pad = 4 // tunable
    const gap = 2 // tunable
    const slot = w / n
    const barW = Math.max(DOT, Math.floor(slot) - gap)
    for (let i = 0; i < n; i++) {
      let yTop = h
      const x0 = Math.floor(i * slot)
      for (const s of this.seriesValue) {
        const v = s.values[i] || 0
        if (v === 0) continue
        const segH = (v / max) * (h - pad)
        const yStart = yTop - segH
        ctx.fillStyle = s.color
        for (let x = x0; x < x0 + barW; x += DOT) {
          for (let y = Math.ceil(yStart / DOT) * DOT; y < yTop; y += DOT) {
            const fade = 1 - (y - yStart) / (segH || 1)
            this.dot(ctx, x, y, 0.45 + 0.5 * fade) // tunable intensity range
          }
        }
        yTop = yStart
      }
    }
  }
}
