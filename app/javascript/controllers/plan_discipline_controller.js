import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["nonEvent", "event"]

  connect() {
    this.update()
  }

  update() {
    const event = this.element.querySelector('input[name="plan_configuration[goal]"]:checked')?.value === "event"
    // Retain both selections in the draft when switching goals.
    this.nonEventTarget.hidden = event
    this.eventTarget.hidden = !event
  }
}
