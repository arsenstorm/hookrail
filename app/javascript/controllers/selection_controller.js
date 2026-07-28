import { Controller } from "@hotwired/stimulus"

// Row selection for the events table. Click toggles one row, shift+click takes
// the range from the last clicked row to this one (which wins the state), and
// the action bar is revealed by the count rather than by the DOM, so the
// "all matching these filters" mode can keep it open on its own.
export default class extends Controller {
  static targets = ["row", "all", "bar", "count", "confirm", "pageNote", "allNote", "allFiltered"]
  static values = { total: Number }

  connect() {
    this.allFiltered = false
    this.anchor = -1
    this.refresh()
  }

  disconnect() {
    document.documentElement.removeAttribute("data-selecting")
  }

  // The whole cell is the hit area, so the checkbox may or may not be what was
  // clicked; the browser has already flipped it when it was.
  toggleRow(event) {
    const box = event.currentTarget.querySelector("input[type=checkbox]")
    if (event.target !== box) box.checked = !box.checked

    const index = this.rowTargets.indexOf(box)
    if (event.shiftKey && this.anchor >= 0 && this.anchor !== index) {
      const [from, to] = [this.anchor, index].sort((a, b) => a - b)
      this.rowTargets.slice(from, to + 1).forEach((other) => (other.checked = box.checked))
    }
    this.anchor = index
    this.allFiltered = false
    this.refresh()
  }

  toggleAll(event) {
    const box = this.allTarget
    if (event.target !== box) box.checked = !box.checked
    this.rowTargets.forEach((other) => (other.checked = box.checked))
    this.anchor = -1
    this.allFiltered = false
    this.refresh()
  }

  // Drops the row scoping: with no event_ids in the payload the server acts on
  // everything the filters match, which is what the affordance promises.
  selectAllFiltered() {
    this.allFiltered = true
    this.refresh()
  }

  clear() {
    this.rowTargets.forEach((box) => (box.checked = false))
    this.anchor = -1
    this.allFiltered = false
    this.refresh()
  }

  escape(event) {
    if (event.key === "Escape") this.clear()
  }

  refresh() {
    const selected = this.rowTargets.filter((box) => box.checked).length
    const every = selected === this.rowTargets.length

    // A property, not an attribute — there is no HTML for the third state.
    this.allTarget.checked = selected > 0 && every
    this.allTarget.indeterminate = selected > 0 && !every

    const open = selected > 0 || this.allFiltered
    this.barTarget.toggleAttribute("data-open", open)
    this.barTarget.inert = !open
    // The bar is pinned bottom-centre; the flash toasts move up off it. Marking
    // the root keeps it one CSS rule instead of reaching for a sibling element
    // that may not be in the DOM yet.
    document.documentElement.toggleAttribute("data-selecting", open)
    this.countTarget.textContent = this.allFiltered ? this.totalValue : selected

    if (this.hasPageNoteTarget) {
      this.pageNoteTarget.hidden = this.allFiltered || !every
      this.allNoteTarget.hidden = !this.allFiltered
      this.allFilteredTarget.disabled = !this.allFiltered
    }
    this.confirmTargets.forEach((button) => {
      button.dataset.turboConfirm = this.allFiltered ? button.dataset.confirmAll : button.dataset.confirmSelected
    })
  }
}
