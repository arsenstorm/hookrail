import { Controller } from "@hotwired/stimulus"

// Flash toasts: they leave on their own after a pause, and hovering holds one
// open long enough to read it.
export default class extends Controller {
  static values = { delay: { type: Number, default: 5000 } }

  connect() { this.resume() }
  disconnect() { this.pause() }

  pause() { clearTimeout(this.timer) }
  resume() { this.timer = setTimeout(() => this.dismiss(), this.delayValue) }

  dismiss() {
    this.pause()
    this.element.classList.add("opacity-0", "translate-y-2")
    // ponytail: fixed timeout rather than transitionend — reduced motion never fires one.
    setTimeout(() => this.element.remove(), 150)
  }
}
