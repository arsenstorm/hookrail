import { Controller } from "@hotwired/stimulus"

// Opens a native <dialog> as a modal. Esc closes it natively; Cancel buttons
// call close. `open: true` (server-rendered when the form inside has errors)
// reopens it on load so a validation failure is never hidden.
export default class extends Controller {
  static targets = ["dialog"]
  static values = { open: Boolean }

  connect() {
    if (this.openValue) this.dialogTarget.showModal()
  }

  open() { this.dialogTarget.showModal() }
  close() { this.dialogTarget.close() }
}
