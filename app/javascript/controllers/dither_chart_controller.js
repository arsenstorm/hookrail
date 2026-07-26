import { Controller } from "@hotwired/stimulus"

// Dithered canvas charts: an ordered Bayer 4x4 threshold matrix turns flat
// fills into a halftone dot texture — full density at the data line fading
// toward the baseline — instead of smooth gradients.
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

export default class extends Controller {
  static values = { type: String, labels: Array, series: Array }

  connect() {
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

  draw() {
    const canvas = this.element
    const dpr = window.devicePixelRatio || 1
    const w = canvas.clientWidth
    const h = canvas.clientHeight
    if (w === 0 || this.seriesValue.length === 0) return
    canvas.width = w * dpr
    canvas.height = h * dpr
    const ctx = canvas.getContext("2d")
    ctx.scale(dpr, dpr)
    ctx.clearRect(0, 0, w, h)
    // The canvas element's own text color carries the theme-aware axis color.
    this.axisColor = getComputedStyle(canvas).color
    if (this.typeValue === "bars") this.drawBars(ctx, w, h)
    else this.drawArea(ctx, w, h)
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
