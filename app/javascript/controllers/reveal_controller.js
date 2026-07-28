import { Controller } from "@hotwired/stimulus"

// Shows the section whose data-reveal-name matches the select's value.
export default class extends Controller {
  static targets = ["select", "section"]

  connect() { this.update() }

  update() {
    const value = this.selectTarget.value
    this.sectionTargets.forEach((el) => (el.hidden = el.dataset.revealName !== value))
  }
}
