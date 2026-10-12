import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import { test } from "node:test"

// Stub only Stimulus' base class; exercise the shipped controller without a DOM dependency.
const source = await readFile(new URL("../../app/javascript/controllers/plan_configuration_controller.js", import.meta.url), "utf8")
const base = "data:text/javascript,export class Controller {}"
const { default: PlanConfiguration } = await import(`data:text/javascript;base64,${Buffer.from(source.replace('"@hotwired/stimulus"', JSON.stringify(base))).toString("base64")}`)

function fixture() {
  const controller = new PlanConfiguration()
  const goal = { value: "increase_ftp" }
  const controls = []
  controller.element = { querySelector: () => goal, querySelectorAll: () => controls }
  for (const target of ["duration", "event", "custom", "eventTiming", "endDate", "optionalDetails", "disclosureState", "cycle", "phaseSequence"]) controller[`${target}Target`] = {}
  controller.baseTarget = { checked: true }
  controller.progressionTargets = [{ value: "continuous", checked: true }, { value: "hard_recovery_cycle", checked: false }]
  controller.cycleWeeksTarget = { value: "3" }
  controller.lengthTarget = { value: "3" }
  controller.weeksTarget = { value: "8" }
  controller.startDateTarget = { value: "2028-01-31" }
  controller.endDateUrlValue = "/training_plan/end_date"
  return { controller, goal, controls }
}

test("goal and length changes disable only inactive sections and preserve entered values", () => {
  const { controller, goal } = fixture()
  controller.refreshEndDate = () => {}
  controller.update()
  assert.equal(controller.eventTarget.disabled, true)
  assert.equal(controller.durationTarget.disabled, false)
  assert.equal(controller.customTarget.hidden, true)
  controller.lengthTarget.value = "custom"
  controller.update()
  assert.equal(controller.customTarget.disabled, false)
  goal.value = "event"
  controller.update()
  assert.equal(controller.durationTarget.disabled, true)
  assert.equal(controller.customTarget.disabled, true)
  assert.equal(controller.eventTarget.disabled, false)
  assert.equal(controller.eventTimingTarget.hidden, false)
  goal.value = "improve_climbing"
  controller.update()
  assert.equal(controller.customTarget.disabled, false)
  assert.equal(controller.weeksTarget.value, "8")
  assert.equal(controller.lengthTarget.value, "custom")
})

test("CYF-89 reveals the cycle field only in cycle mode and retains its value when toggled", () => {
  const { controller } = fixture()
  controller.refreshEndDate = () => {}
  controller.update()
  assert.equal(controller.cycleTarget.hidden, true)
  assert.equal(controller.cycleTarget.disabled, true)
  controller.progressionTargets[0].checked = false
  controller.progressionTargets[1].checked = true
  controller.update()
  assert.equal(controller.cycleTarget.hidden, false)
  assert.equal(controller.cycleTarget.disabled, false)
  controller.cycleWeeksTarget.value = "4"
  controller.progressionTargets[0].checked = true
  controller.progressionTargets[1].checked = false
  controller.update()
  assert.equal(controller.cycleTarget.hidden, true)
  assert.equal(controller.cycleWeeksTarget.value, "4")
})

test("CYF-89 announces the selected phase sequence including event taper", () => {
  const { controller, goal } = fixture()
  controller.refreshEndDate = () => {}
  controller.update()
  assert.match(controller.phaseSequenceTarget.textContent, /Base.*Build.*Speciality/)
  controller.baseTarget.checked = false
  controller.update()
  assert.match(controller.phaseSequenceTarget.textContent, /Build.*Speciality/)
  assert.doesNotMatch(controller.phaseSequenceTarget.textContent, /Base/)
  goal.value = "event"
  controller.update()
  assert.match(controller.phaseSequenceTarget.textContent, /Build.*Speciality.*Taper/)
})

test("disabled values survive form submission as draft data without duplicate active fields", () => {
  const { controller, controls } = fixture()
  controls.push(
    { name: "event_name", value: "Saved event", type: "text" },
    { name: "custom_duration_weeks", value: "2.5", type: "number" },
    { name: "length", value: "stale", type: "select-one" },
    { name: "unchecked", value: "0", type: "radio", checked: false }
  )
  const formData = new FormData()
  formData.set("length", "3")
  controller.preserveDraft({ formData })
  assert.equal(formData.get("event_name"), "Saved event")
  assert.equal(formData.get("custom_duration_weeks"), "2.5")
  assert.deepEqual(formData.getAll("length"), ["3"])
  assert.equal(formData.has("unchecked"), false)
})

test("optional disclosure state survives submit and reveals invalid optional controls", () => {
  const { controller } = fixture()
  controller.optionalDetailsTarget.open = true
  controller.prepareSubmit()
  assert.equal(controller.disclosureStateTarget.value, "1")
  controller.optionalDetailsTarget.open = false
  controller.disclose()
  assert.equal(controller.disclosureStateTarget.value, "0")
  controller.revealOptional()
  assert.equal(controller.optionalDetailsTarget.open, true)
})

test("end-date display uses Rails' response and clears invalid inputs", async () => {
  const { controller } = fixture()
  globalThis.window = { location: { origin: "http://localhost" } }
  const originalFetch = globalThis.fetch
  try {
    globalThis.fetch = async url => {
      assert.equal(url.searchParams.get("starts_on"), "2028-01-31")
      assert.equal(url.searchParams.get("plan_length"), "3")
      return { ok: true, json: async () => ({ label: "April 29, 2028" }) }
    }
    await controller.refreshEndDate()
    assert.equal(controller.endDateTarget.textContent, "Plan ends on April 29, 2028")
    globalThis.fetch = async () => ({ ok: true, json: async () => ({ label: null }) })
    await controller.refreshEndDate()
    assert.equal(controller.endDateTarget.textContent, "Choose a valid start date and plan length to see the end date.")
    globalThis.fetch = async () => ({ ok: false })
    await controller.refreshEndDate()
    assert.equal(controller.endDateTarget.textContent, "Preview your plan to check its end date.")
  } finally {
    globalThis.fetch = originalFetch
  }
})

test("goal switching aborts an outstanding end-date request and event mode makes no request", async () => {
  const { controller } = fixture()
  globalThis.window = { location: { origin: "http://localhost" } }
  const originalFetch = globalThis.fetch
  let signal
  try {
    globalThis.fetch = (_url, options) => {
      signal = options.signal
      return new Promise((_resolve, reject) => signal.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError"))))
    }
    const pending = controller.refreshEndDate()
    controller.durationTarget.disabled = true
    await controller.refreshEndDate()
    await pending
    assert.equal(signal.aborted, true)
    controller.disconnect()
  } finally {
    globalThis.fetch = originalFetch
  }
})

test("summary refresh posts active form choices and replaces only the summary", async () => {
  const { controller } = fixture()
  controller.summaryTarget = { innerHTML: "old summary" }
  controller.summaryUrlValue = "/training_plan/summary"
  const originalFetch = globalThis.fetch
  const originalFormData = globalThis.FormData
  try {
    globalThis.FormData = class { constructor(form) { assert.equal(form, controller.element) } }
    globalThis.fetch = async (url, options) => {
      assert.equal(url, "/training_plan/summary")
      assert.equal(options.method, "POST")
      assert.equal(options.headers.Accept, "text/html")
      return { ok: true, text: async () => "<section>Updated summary</section>" }
    }
    await controller.refreshSummary()
    assert.equal(controller.summaryTarget.innerHTML, "<section>Updated summary</section>")
  } finally {
    globalThis.fetch = originalFetch
    globalThis.FormData = originalFormData
  }
})
