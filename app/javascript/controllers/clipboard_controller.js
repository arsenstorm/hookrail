import { Controller } from "@hotwired/stimulus"

// Copy-to-clipboard with a 1.5s checkmark confirmation. Both icons ship in the
// markup so confirming is a class toggle rather than building DOM.
export default class extends Controller {
  static targets = ["copy", "done"]
  static values = { text: String }

  async copy() {
    await navigator.clipboard.writeText(this.textValue)
    this.toggle(true)
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.toggle(false), 1500)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  toggle(copied) {
    this.copyTarget.classList.toggle("hidden", copied)
    this.doneTarget.classList.toggle("hidden", !copied)
  }
}
