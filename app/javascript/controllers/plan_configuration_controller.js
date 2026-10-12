import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["duration", "event", "eventTiming", "custom", "length", "weeks", "startDate", "endDate", "optionalDetails", "disclosureState", "base", "phaseSequence", "progression", "cycle"]
  static values = { endDateUrl: String }

  connect() {
    this.update()
  }

  disconnect() {
    this.endDateRequest?.abort()
  }

  update() {
    const event = this.element.querySelector('input[name="plan_configuration[goal]"]:checked')?.value === "event"
    this.setActive(this.durationTarget, !event)
    this.setActive(this.eventTarget, event)
    this.setActive(this.customTarget, !event && this.lengthTarget.value === "custom")
    this.setActive(this.cycleTarget, this.progressionTargets.find(option => option.checked)?.value === "hard_recovery_cycle")
    this.phaseSequenceTarget.textContent = `Phases: ${this.baseTarget.checked ? "Base → " : ""}Build → Speciality${event ? " → Taper" : ""}.`
    this.eventTimingTarget.hidden = !event
    this.refreshEndDate()
  }

  setActive(fieldset, active) {
    fieldset.hidden = !active
    fieldset.disabled = !active
  }

  // Disabled controls stay out of native validation and keyboard navigation.
  // Carry their values as draft data; Rails alone decides which inputs are active.
  preserveDraft(event) {
    this.element.querySelectorAll("input:disabled, select:disabled").forEach(control => {
      if (!control.name || event.formData.has(control.name)) return
      if (["radio", "checkbox"].includes(control.type) && !control.checked) return
      event.formData.append(control.name, control.value)
    })
  }

  disclose() {
    this.disclosureStateTarget.value = this.optionalDetailsTarget.open ? "1" : "0"
  }

  revealOptional() {
    this.optionalDetailsTarget.open = true
  }

  prepareSubmit() {
    this.disclose()
  }

  async refreshEndDate() {
    this.endDateRequest?.abort()
    if (this.durationTarget.disabled) return

    this.endDateRequest = new AbortController()
    const url = new URL(this.endDateUrlValue, window.location.origin)
    url.search = new URLSearchParams({
      starts_on: this.startDateTarget.value,
      plan_length: this.lengthTarget.value,
      custom_duration_weeks: this.weeksTarget.value
    })
    this.endDateTarget.textContent = "Calculating plan end date…"
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, signal: this.endDateRequest.signal })
      if (!response.ok) throw new Error("End date unavailable")
      const result = await response.json()
      this.endDateTarget.textContent = result.label ? `Plan ends on ${result.label}` : "Choose a valid start date and plan length to see the end date."
    } catch (error) {
      if (error.name !== "AbortError") this.endDateTarget.textContent = "Preview your plan to check its end date."
    }
  }
}
