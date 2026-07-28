import Dropdown from "@stimulus-components/dropdown"

// @stimulus-components/dropdown handles open/close, enter/leave transitions,
// and click-outside. It leaves out the accessibility half, so this adds it:
// aria-expanded on the trigger, Escape to close, and focus returning to the
// trigger when it does.
export default class extends Dropdown {
  static targets = ["menu", "trigger"]

  connect() {
    super.connect()
    this.expanded = false
    this.sync()
  }

  toggle() {
    super.toggle()
    this.expanded = !this.expanded
    this.sync()
  }

  hide(event) {
    if (!this.expanded || this.element.contains(event.target)) return
    super.hide(event)
    this.expanded = false
    this.sync()
  }

  escape(event) {
    if (event.key !== "Escape" || !this.expanded) return
    this.leave()
    this.expanded = false
    this.sync()
    this.triggerTarget.focus()
  }

  // Tracked here rather than read off the class list: the hidden class lands
  // after the leave transition resolves, so the DOM lies for ~100ms.
  sync() {
    this.triggerTarget.setAttribute("aria-expanded", String(this.expanded))
  }
}
