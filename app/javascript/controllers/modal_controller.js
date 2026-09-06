import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["closeButton"]

  connect() {
    this.closeButtonTarget.focus()
  }

  close(event) {
    event.preventDefault()
    this.element.closest("turbo-frame").innerHTML = ""
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.close(event)
      return
    }
    if (event.key !== "Tab") return

    const focusable = this.element.querySelectorAll("a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled])")
    const first = focusable[0]
    const last = focusable[focusable.length - 1]
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }
}
