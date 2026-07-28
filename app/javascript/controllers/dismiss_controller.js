import { Controller } from "@hotwired/stimulus"

// Light dismiss for <details> menus: a click anywhere outside closes it, and
// Escape closes it and returns focus to the trigger. <details> gives us the
// open/close state, keyboard toggle, and no-JS fallback for free — this fills
// in the two behaviours it lacks.
export default class extends Controller {
  connect() {
    this.onPointerDown = (event) => {
      if (this.element.open && !this.element.contains(event.target)) this.element.open = false
    }
    this.onKeyDown = (event) => {
      if (event.key !== "Escape" || !this.element.open) return
      this.element.open = false
      this.element.querySelector("summary")?.focus()
    }
    document.addEventListener("pointerdown", this.onPointerDown)
    document.addEventListener("keydown", this.onKeyDown)
  }

  disconnect() {
    document.removeEventListener("pointerdown", this.onPointerDown)
    document.removeEventListener("keydown", this.onKeyDown)
  }
}
