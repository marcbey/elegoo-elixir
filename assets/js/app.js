// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/elegoo_elixir"
import topbar from "../vendor/topbar"

const clamp = (value, min, max) => Math.min(max, Math.max(min, value))

const Joystick = {
  mounted() {
    this.area = this.el.querySelector("[data-joystick-area]") || this.el
    this.knob = this.el.querySelector("[data-joystick-knob]")
    this.pointerId = null
    this.radius = this.computeRadius()
    this.lastPush = 0
    this.pushIntervalMs = 28
    this.lastPayload = null

    this.onPointerDown = (event) => {
      if (this.pointerId !== null) return

      this.pointerId = event.pointerId
      try {
        this.area.setPointerCapture(event.pointerId)
      } catch (_error) {
      }
      this.lastPayload = null
      this.updateFromEvent(event, true)
      event.preventDefault()
    }

    this.onPointerMove = (event) => {
      if (event.pointerId !== this.pointerId) return
      this.updateFromEvent(event, false)
      event.preventDefault()
    }

    this.onPointerUp = (event) => {
      this.finishInteraction(event)
    }

    this.onLostPointerCapture = () => {
      this.finishInteraction()
    }

    this.onResize = () => {
      this.radius = this.computeRadius()

      if (this.pointerId === null) {
        this.centerKnob()
      }
    }

    this.onVisibilityChange = () => {
      if (document.hidden && this.pointerId !== null) {
        this.pointerId = null
        this.centerKnob()
        this.pushEvent("joystick_release", {})
      }
    }

    this.onWindowBlur = () => {
      if (this.pointerId !== null) {
        this.pointerId = null
        this.centerKnob()
        this.pushEvent("joystick_release", {})
      }
    }

    this.area.addEventListener("pointerdown", this.onPointerDown)
    this.area.addEventListener("pointermove", this.onPointerMove)
    this.area.addEventListener("pointerup", this.onPointerUp)
    this.area.addEventListener("pointercancel", this.onPointerUp)
    this.area.addEventListener("lostpointercapture", this.onLostPointerCapture)
    window.addEventListener("resize", this.onResize)
    window.addEventListener("blur", this.onWindowBlur)
    document.addEventListener("visibilitychange", this.onVisibilityChange)
    this.centerKnob()
  },

  destroyed() {
    this.area.removeEventListener("pointerdown", this.onPointerDown)
    this.area.removeEventListener("pointermove", this.onPointerMove)
    this.area.removeEventListener("pointerup", this.onPointerUp)
    this.area.removeEventListener("pointercancel", this.onPointerUp)
    this.area.removeEventListener("lostpointercapture", this.onLostPointerCapture)
    window.removeEventListener("resize", this.onResize)
    window.removeEventListener("blur", this.onWindowBlur)
    document.removeEventListener("visibilitychange", this.onVisibilityChange)
  },

  computeRadius() {
    const areaRect = this.area.getBoundingClientRect()
    const knobRect = this.knob?.getBoundingClientRect() || {width: 0}
    const maxTravel = (Math.min(areaRect.width, areaRect.height) - knobRect.width) / 2
    return Math.max(18, maxTravel)
  },

  centerKnob() {
    if (!this.knob) return
    this.knob.style.transform = "translate(0px, 0px)"
  },

  updateFromEvent(event, forcePush) {
    if (!this.knob) return

    const rect = this.area.getBoundingClientRect()
    const centerX = rect.left + rect.width / 2
    const centerY = rect.top + rect.height / 2

    const dx = event.clientX - centerX
    const dy = event.clientY - centerY
    const distance = Math.hypot(dx, dy)
    const limitedDistance = Math.min(distance, this.radius)
    const scale = distance > 0 ? limitedDistance / distance : 0
    const clampedDx = dx * scale
    const clampedDy = dy * scale

    this.knob.style.transform = `translate(${clampedDx.toFixed(1)}px, ${clampedDy.toFixed(1)}px)`

    const normalizedX = clamp(clampedDx / this.radius, -1, 1)
    const normalizedY = clamp(-clampedDy / this.radius, -1, 1)
    const now = performance.now()
    const payload = {
      x: normalizedX.toFixed(3),
      y: normalizedY.toFixed(3),
    }
    const changed =
      this.lastPayload === null ||
      payload.x !== this.lastPayload.x ||
      payload.y !== this.lastPayload.y

    if ((forcePush || now - this.lastPush >= this.pushIntervalMs) && changed) {
      this.lastPush = now
      this.lastPayload = payload
      this.pushEvent("joystick_move", payload)
    }
  },

  finishInteraction(event) {
    if (event && event.pointerId !== this.pointerId) return
    if (this.pointerId === null) return

    const pointerId = this.pointerId
    this.pointerId = null
    this.lastPayload = null

    try {
      this.area.releasePointerCapture(pointerId)
    } catch (_error) {
    }

    this.centerKnob()
    this.pushEvent("joystick_release", {})

    if (event) {
      event.preventDefault()
    }
  },
}

const CameraPanSlider = {
  mounted() {
    this.lastPan = this.el.value

    this.onInput = () => {
      const pan = this.el.value
      if (pan === this.lastPan) return

      this.lastPan = pan
      this.pushEvent("camera_pan", {pan})
    }

    this.el.addEventListener("input", this.onInput)
  },

  updated() {
    this.lastPan = this.el.value
  },

  destroyed() {
    this.el.removeEventListener("input", this.onInput)
  },
}

const EmergencyStopButton = {
  mounted() {
    this.feedbackTimer = null

    this.onClick = () => {
      this.el.classList.remove("is-feedback")
      void this.el.offsetWidth
      this.el.classList.add("is-feedback")

      clearTimeout(this.feedbackTimer)
      this.feedbackTimer = setTimeout(() => {
        this.el.classList.remove("is-feedback")
      }, 220)
    }

    this.el.addEventListener("click", this.onClick)
  },

  destroyed() {
    clearTimeout(this.feedbackTimer)
    this.el.removeEventListener("click", this.onClick)
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Joystick, CameraPanSlider, EmergencyStopButton},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
