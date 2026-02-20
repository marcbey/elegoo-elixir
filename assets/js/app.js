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

const SpeechPushToTalk = {
  mounted() {
    this.endpoint = this.el.dataset.endpoint || "/api/speech/transcribe"
    this.maxClipMs = Number.parseInt(this.el.dataset.maxClipMs || "4500", 10)
    this.csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""
    this.targetSampleRate = 16_000

    this.speechStartThreshold = 0.03
    this.speechContinueThreshold = 0.02
    this.minSpeechMs = 250
    this.silenceStopMs = 800
    this.preRollMs = 320

    this.voicePanel = this.el.closest("[data-voice-panel]") || this.el.parentElement
    this.levelMeterEl = this.voicePanel?.querySelector("[data-voice-level-meter]") || null
    this.levelFillEl = this.voicePanel?.querySelector("[data-voice-level-fill]") || null

    this.mediaStream = null
    this.audioContext = null
    this.audioSource = null
    this.audioAnalyser = null
    this.audioProcessor = null
    this.audioMuteNode = null
    this.captureSampleRate = this.targetSampleRate

    this.levelData = null
    this.levelFrame = null
    this.levelSmooth = 0

    this.isListeningEnabled = false
    this.isProcessing = false
    this.processingQueue = false
    this.latestFrameRms = 0

    this.segmentActive = false
    this.segmentChunks = []
    this.segmentSamples = 0
    this.segmentStartedAt = 0
    this.segmentLastSpeechAt = 0

    this.preRollChunks = []
    this.preRollSamples = 0
    this.uploadQueue = []

    const AudioCtx = window.AudioContext || window.webkitAudioContext
    if (!AudioCtx || !navigator.mediaDevices?.getUserMedia) {
      this.setVisualState("unsupported")
      this.pushEvent("voice_state", {state: "unsupported"})
      this.el.disabled = true
      return
    }

    this.setVisualState("idle")
    this.setLevel(0)

    // Auto-enable always-on hands-free mode.
    void this.enableHandsFree()
  },

  destroyed() {
    this.isListeningEnabled = false
    this.endSegment({enqueue: false})
    this.uploadQueue = []
    this.stopLevelLoop()
    this.stopStream()
  },

  async enableHandsFree() {
    if (this.isListeningEnabled) return

    try {
      await this.ensureStream()
      this.isListeningEnabled = true
      this.startLevelLoop()
      this.setVisualState("listening")
      this.pushEvent("voice_state", {state: "listening"})
    } catch (error) {
      this.isListeningEnabled = false
      this.setVisualState("idle")
      this.pushEvent("voice_state", {state: "idle"})
      this.pushEvent("voice_error", {message: this.errorMessage(error)})
    }
  },

  async ensureStream() {
    if (this.mediaStream) return this.mediaStream

    this.mediaStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        channelCount: 1,
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
      },
      video: false,
    })

    await this.ensureAudioPipeline()
    return this.mediaStream
  },

  stopStream() {
    if (!this.mediaStream) return

    this.mediaStream.getTracks().forEach(track => track.stop())
    this.mediaStream = null

    this.audioSource?.disconnect()
    this.audioAnalyser?.disconnect()
    this.audioProcessor?.disconnect()
    this.audioMuteNode?.disconnect()

    this.audioSource = null
    this.audioAnalyser = null
    this.audioProcessor = null
    this.audioMuteNode = null
    this.levelData = null
    this.captureSampleRate = this.targetSampleRate

    if (this.audioContext) {
      void this.audioContext.close().catch(() => {})
      this.audioContext = null
    }
  },

  async ensureAudioPipeline() {
    if (!this.mediaStream) return

    const AudioCtx = window.AudioContext || window.webkitAudioContext
    if (!AudioCtx) return

    if (!this.audioContext) {
      this.audioContext = new AudioCtx()
    }

    if (this.audioContext.state === "suspended") {
      await this.audioContext.resume()
    }

    if (this.audioAnalyser && this.audioProcessor) return

    this.audioSource = this.audioContext.createMediaStreamSource(this.mediaStream)
    this.audioAnalyser = this.audioContext.createAnalyser()
    this.audioAnalyser.fftSize = 1024
    this.audioAnalyser.smoothingTimeConstant = 0.78

    this.audioProcessor = this.audioContext.createScriptProcessor(4096, 1, 1)
    this.audioMuteNode = this.audioContext.createGain()
    this.audioMuteNode.gain.value = 0
    this.captureSampleRate = this.audioContext.sampleRate || this.targetSampleRate

    this.audioProcessor.onaudioprocess = (event) => {
      const input = event.inputBuffer.getChannelData(0)
      if (!input || input.length === 0) return

      const copy = new Float32Array(input.length)
      copy.set(input)
      const rms = this.computeRms(copy)
      this.latestFrameRms = rms
      this.trackPreRoll(copy)

      if (!this.isListeningEnabled) return
      this.handleSegmentFrame(copy, rms)
    }

    this.audioSource.connect(this.audioAnalyser)
    this.audioSource.connect(this.audioProcessor)
    this.audioProcessor.connect(this.audioMuteNode)
    this.audioMuteNode.connect(this.audioContext.destination)
    this.levelData = new Uint8Array(this.audioAnalyser.fftSize)
  },

  startLevelLoop() {
    if (!this.audioAnalyser || this.levelFrame !== null) return

    const tick = () => {
      if (!this.audioAnalyser || !this.levelData || (!this.isListeningEnabled && !this.isProcessing)) {
        this.levelFrame = null
        this.setLevel(0)
        return
      }

      this.audioAnalyser.getByteTimeDomainData(this.levelData)

      let sum = 0
      for (let i = 0; i < this.levelData.length; i += 1) {
        const centered = (this.levelData[i] - 128) / 128
        sum += centered * centered
      }

      const rms = Math.sqrt(sum / this.levelData.length)
      const normalized = clamp((rms - 0.01) * 8.5, 0, 1)
      this.levelSmooth = this.levelSmooth * 0.72 + normalized * 0.28
      this.setLevel(this.levelSmooth)

      this.levelFrame = window.requestAnimationFrame(tick)
    }

    this.levelFrame = window.requestAnimationFrame(tick)
  },

  stopLevelLoop() {
    if (this.levelFrame !== null) {
      window.cancelAnimationFrame(this.levelFrame)
      this.levelFrame = null
    }

    this.levelSmooth = 0
    this.setLevel(0)
  },

  trackPreRoll(chunk) {
    if (this.segmentActive) return

    this.preRollChunks.push(chunk)
    this.preRollSamples += chunk.length

    const maxPreRollSamples = Math.max(
      1,
      Math.round((this.captureSampleRate * this.preRollMs) / 1000)
    )

    while (this.preRollSamples > maxPreRollSamples && this.preRollChunks.length > 0) {
      const removed = this.preRollChunks.shift()
      this.preRollSamples -= removed.length
    }
  },

  handleSegmentFrame(chunk, rms) {
    const now = performance.now()

    if (!this.segmentActive) {
      if (rms >= this.speechStartThreshold) {
        this.startSegment(now, chunk)
      }
      return
    }

    this.segmentChunks.push(chunk)
    this.segmentSamples += chunk.length

    if (rms >= this.speechContinueThreshold) {
      this.segmentLastSpeechAt = now
    }

    const utteranceMs = now - this.segmentStartedAt
    const trailingSilenceMs = now - this.segmentLastSpeechAt

    if (utteranceMs >= this.maxClipMs || trailingSilenceMs >= this.silenceStopMs) {
      this.endSegment({enqueue: true})
    }
  },

  startSegment(startedAt, firstChunk) {
    this.segmentActive = true
    this.segmentStartedAt = startedAt
    this.segmentLastSpeechAt = startedAt
    this.segmentChunks = []
    this.segmentSamples = 0

    if (this.preRollChunks.length > 0) {
      for (const preChunk of this.preRollChunks) {
        this.segmentChunks.push(preChunk)
        this.segmentSamples += preChunk.length
      }
    }

    this.segmentChunks.push(firstChunk)
    this.segmentSamples += firstChunk.length
  },

  endSegment({enqueue}) {
    if (!this.segmentActive) return

    const chunks = this.segmentChunks
    const totalSamples = this.segmentSamples
    const durationMs = (totalSamples / this.captureSampleRate) * 1000

    this.segmentActive = false
    this.segmentChunks = []
    this.segmentSamples = 0
    this.segmentStartedAt = 0
    this.segmentLastSpeechAt = 0
    this.preRollChunks = []
    this.preRollSamples = 0

    if (!enqueue || totalSamples <= 0 || durationMs < this.minSpeechMs) {
      return
    }

    const blob = this.buildWavBlobFromChunks(chunks, totalSamples)
    if (!blob) return

    this.uploadQueue.push(blob)
    void this.processUploadQueue()
  },

  async processUploadQueue() {
    if (this.processingQueue) return
    this.processingQueue = true

    while (this.uploadQueue.length > 0) {
      const blob = this.uploadQueue.shift()
      this.isProcessing = true
      this.setVisualState("processing")
      this.pushEvent("voice_state", {state: "processing"})

      await this.uploadBlob(blob)
    }

    this.processingQueue = false
    this.isProcessing = false

    if (this.isListeningEnabled) {
      this.setVisualState("listening")
      this.pushEvent("voice_state", {state: "listening"})
    } else {
      this.setVisualState("idle")
      this.pushEvent("voice_state", {state: "idle"})
    }
  },

  async uploadBlob(blob) {
    const formData = new FormData()
    formData.append("audio", blob, "voice-command.wav")

    try {
      const response = await fetch(this.endpoint, {
        method: "POST",
        headers: {
          "accept": "application/json",
          "x-csrf-token": this.csrfToken,
        },
        credentials: "same-origin",
        body: formData,
      })

      const payload = await response.json().catch(() => ({}))

      if (!response.ok) {
        throw new Error(payload.error || `STT-Request failed (${response.status})`)
      }

      this.pushEvent("voice_transcript", {text: payload.text || ""})
    } catch (error) {
      this.pushEvent("voice_error", {message: this.errorMessage(error)})
    }
  },

  setVisualState(state) {
    this.el.classList.toggle("is-recording", state === "listening")
    this.el.classList.toggle("is-processing", state === "processing")
    this.el.dataset.voiceState = state
  },

  computeRms(samples) {
    if (!samples || samples.length === 0) return 0

    let sum = 0
    for (let i = 0; i < samples.length; i += 1) {
      const s = samples[i]
      sum += s * s
    }

    return Math.sqrt(sum / samples.length)
  },

  buildWavBlobFromChunks(chunks, totalSamples) {
    if (!Array.isArray(chunks) || chunks.length === 0 || totalSamples <= 0) {
      return null
    }

    const merged = this.mergePcmChunks(chunks, totalSamples)
    if (!merged || merged.length === 0) return null

    const samples = this.downsampleIfNeeded(merged, this.captureSampleRate, this.targetSampleRate)
    const wavBuffer = this.encodeWav(samples, this.targetSampleRate)
    return new Blob([wavBuffer], {type: "audio/wav"})
  },

  mergePcmChunks(chunks, totalLength) {
    if (!Array.isArray(chunks) || chunks.length === 0 || totalLength <= 0) {
      return null
    }

    const merged = new Float32Array(totalLength)
    let offset = 0

    for (const chunk of chunks) {
      merged.set(chunk, offset)
      offset += chunk.length
    }

    return merged
  },

  downsampleIfNeeded(source, sourceRate, targetRate) {
    if (!source || source.length === 0) return new Float32Array()
    if (!sourceRate || sourceRate <= targetRate) return source

    const ratio = sourceRate / targetRate
    const targetLength = Math.max(1, Math.round(source.length / ratio))
    const output = new Float32Array(targetLength)
    let sourceOffset = 0

    for (let i = 0; i < targetLength; i += 1) {
      const nextOffset = Math.min(source.length, Math.round((i + 1) * ratio))
      let sum = 0
      let count = 0

      for (let j = sourceOffset; j < nextOffset; j += 1) {
        sum += source[j]
        count += 1
      }

      output[i] = count > 0 ? sum / count : 0
      sourceOffset = nextOffset
    }

    return output
  },

  encodeWav(samples, sampleRate) {
    const bytesPerSample = 2
    const buffer = new ArrayBuffer(44 + samples.length * bytesPerSample)
    const view = new DataView(buffer)
    const blockAlign = bytesPerSample
    const byteRate = sampleRate * blockAlign

    let offset = 0
    const writeAscii = (text) => {
      for (let i = 0; i < text.length; i += 1) {
        view.setUint8(offset + i, text.charCodeAt(i))
      }
      offset += text.length
    }

    writeAscii("RIFF")
    view.setUint32(offset, 36 + samples.length * bytesPerSample, true)
    offset += 4
    writeAscii("WAVE")
    writeAscii("fmt ")
    view.setUint32(offset, 16, true)
    offset += 4
    view.setUint16(offset, 1, true)
    offset += 2
    view.setUint16(offset, 1, true)
    offset += 2
    view.setUint32(offset, sampleRate, true)
    offset += 4
    view.setUint32(offset, byteRate, true)
    offset += 4
    view.setUint16(offset, blockAlign, true)
    offset += 2
    view.setUint16(offset, 16, true)
    offset += 2
    writeAscii("data")
    view.setUint32(offset, samples.length * bytesPerSample, true)
    offset += 4

    for (let i = 0; i < samples.length; i += 1) {
      const clamped = clamp(samples[i], -1, 1)
      view.setInt16(offset, clamped < 0 ? clamped * 0x8000 : clamped * 0x7FFF, true)
      offset += 2
    }

    return buffer
  },

  setLevel(level) {
    const clampedLevel = clamp(level, 0, 1)
    const percent = Math.round(clampedLevel * 100)

    if (this.levelFillEl) {
      this.levelFillEl.style.width = `${percent}%`
    }

    if (this.levelMeterEl) {
      this.levelMeterEl.setAttribute("aria-valuenow", String(percent))
    }
  },

  errorMessage(error) {
    if (!error) return "Unbekannter Fehler"
    if (typeof error === "string") return error
    if (error.message) return error.message
    return String(error)
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Joystick, CameraPanSlider, EmergencyStopButton, SpeechPushToTalk},
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
