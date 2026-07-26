import { Controller } from "@hotwired/stimulus"

// Saving a source with no signing secret leaves the ingest URL open to anyone
// who finds it, so it asks first. Turbo's document-level submit handler bails
// on events whose default is already prevented, and this listener sits on the
// form itself — so it runs first and blocks Turbo's submission too. The
// requeued requestSubmit() then goes through Turbo normally.
export default class extends Controller {
  static targets = ["secret", "dialog"]

  check(event) {
    if (this.confirmed || this.secretTarget.value.trim() !== "") return
    event.preventDefault()
    this.submitter = event.submitter
    this.dialogTarget.showModal()
  }

  cancel() {
    this.dialogTarget.close()
  }

  proceed() {
    this.confirmed = true
    this.dialogTarget.close()
    this.element.requestSubmit(this.submitter)
  }
}
