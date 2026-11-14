import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { test } from "node:test"

// Stub only Stimulus' base class; exercise the shipped controller without a DOM dependency.
const source = await readFile(new URL("../../app/javascript/controllers/activity_dialog_controller.js", import.meta.url), "utf8")
const base = "data:text/javascript,export class Controller {}"
const { default: ActivityDialog } = await import(`data:text/javascript;base64,${Buffer.from(source.replace('"@hotwired/stimulus"', JSON.stringify(base))).toString("base64")}`)

function fixture() {
  const frame = { attributes: { src: "/activities/1" }, removeAttribute(name) { delete this.attributes[name] } }
  const dialog = {
    modal: false,
    removed: false,
    showModal() { this.modal = true },
    remove() { this.removed = true },
    closest: (selector) => (selector === "turbo-frame" ? frame : null)
  }
  const controller = new ActivityDialog()
  controller.element = dialog
  return { controller, dialog, frame }
}

test("GAR-010 opens the activity detail as a modal when it arrives", () => {
  const { controller, dialog } = fixture()

  controller.connect()

  assert.equal(dialog.modal, true)
})

test("GAR-010 empties the frame on close so the same entry opens again", () => {
  const { controller, dialog, frame } = fixture()

  controller.dismiss()

  assert.equal(dialog.removed, true)
  assert.equal("src" in frame.attributes, false)
})
