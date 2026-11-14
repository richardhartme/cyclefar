import { Controller } from "@hotwired/stimulus"

// Opens the activity detail as a modal and empties its frame on close, so
// the same entry can be opened again.
export default class extends Controller {
  connect() {
    this.element.showModal()
  }

  dismiss() {
    const frame = this.element.closest("turbo-frame")
    frame?.removeAttribute("src")
    this.element.remove()
  }
}
