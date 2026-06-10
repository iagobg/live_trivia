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
import {hooks as colocatedHooks} from "phoenix-colocated/live_trivia"
import topbar from "../vendor/topbar"

const Hooks = {}

const mobileViewportQuery = window.matchMedia("(max-width: 639px)")
const keyboardAwareSelector = ".keyboard-aware-player-screen, .keyboard-aware-join-screen"

const updateVisualViewportVars = () => {
  const viewport = window.visualViewport
  const height = viewport?.height || window.innerHeight
  const offsetTop = viewport?.offsetTop || 0
  const layoutHeight = document.documentElement.clientHeight || window.innerHeight
  const keyboardInset = Math.max(0, layoutHeight - height - offsetTop)
  const root = document.documentElement

  root.style.setProperty("--app-viewport-height", height + "px")
  root.style.setProperty("--app-viewport-offset-top", offsetTop + "px")
  root.style.setProperty("--app-keyboard-inset", keyboardInset + "px")
  root.classList.toggle("keyboard-open", mobileViewportQuery.matches && keyboardInset > 80)
}

updateVisualViewportVars()

if (window.visualViewport) {
  window.visualViewport.addEventListener("resize", updateVisualViewportVars)
  window.visualViewport.addEventListener("scroll", updateVisualViewportVars)
}

window.addEventListener("resize", updateVisualViewportVars)
window.addEventListener("orientationchange", updateVisualViewportVars)
document.addEventListener("focusin", event => {
  if (!event.target.closest?.(keyboardAwareSelector)) return

  setTimeout(updateVisualViewportVars, 50)
})

Hooks.RoomPasswordToggle = {
  mounted() {
    this.checkbox = this.el.querySelector("[data-role='room-password-enabled']")
    this.password = this.el.querySelector("[data-role='room-password']")
    this.toggle = this.toggle.bind(this)

    if (this.checkbox) this.checkbox.addEventListener("change", this.toggle)
    this.toggle()
  },

  updated() {
    this.checkbox = this.el.querySelector("[data-role='room-password-enabled']")
    this.password = this.el.querySelector("[data-role='room-password']")
    this.toggle()
  },

  destroyed() {
    if (this.checkbox) this.checkbox.removeEventListener("change", this.toggle)
  },

  toggle() {
    if (!this.checkbox || !this.password) return

    this.password.disabled = !this.checkbox.checked

    if (!this.checkbox.checked) {
      this.password.value = ""
    }
  },
}

Hooks.PlayerProfileForm = {
  mounted() {
    this.capture()
    this.focusAutofocusInput()
  },

  beforeUpdate() {
    this.capture()
  },

  updated() {
    this.restore()
  },

  capture() {
    const input = this.nameInput()

    if (!input) return

    this.nameValue = input.value
    this.selectionStart = input.selectionStart
    this.selectionEnd = input.selectionEnd
    this.hadFocus = document.activeElement === input
  },

  restore() {
    const input = this.nameInput()

    if (!input || !this.nameValue) return

    input.value = this.nameValue

    if (this.hadFocus) {
      input.focus({preventScroll: true})
      input.setSelectionRange(this.selectionStart, this.selectionEnd)
    }
  },

  focusAutofocusInput() {
    requestAnimationFrame(() => {
      const input = this.nameInput()

      if (input?.hasAttribute("autofocus")) {
        input.focus({preventScroll: true})
      }
    })
  },

  nameInput() {
    return this.el.querySelector("input[name='player[name]']")
  },
}

Hooks.GuessInputFocus = {
  mounted() {
    this.onSubmit = this.onSubmit.bind(this)
    this.onInput = this.onInput.bind(this)
    this.onFocusOut = this.onFocusOut.bind(this)
    this.recentlySubmittedText = null
    this.focusFrame = null

    this.el.addEventListener("submit", this.onSubmit)
    this.el.addEventListener("input", this.onInput)
    this.el.addEventListener("focusout", this.onFocusOut)
    this.focusInput()
  },

  updated() {
    this.clearRehydratedSubmit()
    this.focusInput()
  },

  destroyed() {
    if (this.focusFrame) cancelAnimationFrame(this.focusFrame)

    this.el.removeEventListener("submit", this.onSubmit)
    this.el.removeEventListener("input", this.onInput)
    this.el.removeEventListener("focusout", this.onFocusOut)
  },

  onSubmit() {
    const input = this.guessInput()

    if (!input) return

    this.focusInput(true)

    const submittedText = input.value.trim()

    if (!submittedText) return

    this.recentlySubmittedText = submittedText

    setTimeout(() => {
      const currentInput = this.guessInput()

      if (currentInput && currentInput.value.trim() === submittedText) {
        currentInput.value = ""
      }

      this.focusInput(true)
    }, 0)
  },

  onInput() {
    const input = this.guessInput()

    if (input && input.value.trim() !== "") {
      this.recentlySubmittedText = null
    }
  },

  clearRehydratedSubmit() {
    const input = this.guessInput()

    if (
      input &&
      this.recentlySubmittedText &&
      input.value.trim() === this.recentlySubmittedText
    ) {
      input.value = ""
    }
  },

  onFocusOut() {
    this.focusInput()
  },

  focusInput(force = false) {
    if (this.focusFrame) return

    this.focusFrame = requestAnimationFrame(() => {
      this.focusFrame = null
      const input = this.guessInput()

      if (!input || input.disabled) return
      if (!force && document.activeElement === input) return

      input.focus({preventScroll: true})
    })
  },

  guessInput() {
    return this.el.querySelector("input[name='guess[text]']")
  },
}

Hooks.HintTicker = {
  mounted() {
    this.content = this.el.querySelector(".hint-ticker-content")
    this.updateTicker()
  },

  updated() {
    this.content = this.el.querySelector(".hint-ticker-content")
    this.updateTicker()
  },

  updateTicker() {
    if (!this.content) return

    this.el.classList.remove("is-scrolling")
    this.content.style.removeProperty("--hint-overflow")
    this.content.style.removeProperty("--hint-duration")

    requestAnimationFrame(() => {
      const styles = window.getComputedStyle(this.el)
      const horizontalPadding = parseFloat(styles.paddingLeft) + parseFloat(styles.paddingRight)
      const availableWidth = this.el.clientWidth - horizontalPadding
      const overflow = this.content.scrollWidth - availableWidth

      if (overflow <= 4) return

      this.content.style.setProperty("--hint-overflow", `${overflow}px`)
      this.content.style.setProperty("--hint-duration", "4s")
      this.el.classList.add("is-scrolling")
    })
  },
}

Hooks.TypingBubble = {
  mounted() {
    this.content = this.el.querySelector(".typing-bubble-content")
    this.lastMeasureKey = null
    this.updateBubble()
  },

  updated() {
    this.content = this.el.querySelector(".typing-bubble-content")
    this.updateBubble()
  },

  updateBubble() {
    if (!this.content) return

    const text = this.content.textContent || ""
    const width = this.el.clientWidth
    const measureKey = `${text}:${width}`

    if (measureKey === this.lastMeasureKey) return

    this.lastMeasureKey = measureKey
    this.el.classList.remove("is-overflowing")

    requestAnimationFrame(() => {
      const styles = window.getComputedStyle(this.el)
      const horizontalPadding = parseFloat(styles.paddingLeft) + parseFloat(styles.paddingRight)
      const availableWidth = this.el.clientWidth - horizontalPadding
      const overflow = this.content.scrollWidth - availableWidth

      if (overflow <= 4) return

      this.el.classList.add("is-overflowing")
    })
  },
}

Hooks.RoundMeter = {
  mounted() {
    this.progress = this.el.querySelector("[data-role='timer-progress']")
    this.timer = this.el.querySelector("[data-role='timer-value']")
    this.score = this.el.querySelector("[data-role='score-value']")
    this.shell = this.el.querySelector("[data-role='hub-shell']")
    this.raf = null
    this.lastKey = null
    this.clockOffsetMs = 0
    this.tick = this.tick.bind(this)
    this.start()
  },

  updated() {
    this.progress = this.el.querySelector("[data-role='timer-progress']")
    this.timer = this.el.querySelector("[data-role='timer-value']")
    this.score = this.el.querySelector("[data-role='score-value']")
    this.shell = this.el.querySelector("[data-role='hub-shell']")
    this.start()
  },

  destroyed() {
    this.stop()
  },

  start() {
    this.syncClock()
    const key = `${this.el.dataset.phase}:${this.el.dataset.round}:${this.el.dataset.start}`
    if (key === this.lastKey && this.raf) return

    this.lastKey = key
    this.stop()
    this.tick()
  },

  syncClock() {
    const serverNow = Number(this.el.dataset.serverNow)
    this.clockOffsetMs = serverNow ? Date.now() - serverNow : 0
  },

  stop() {
    if (this.raf) cancelAnimationFrame(this.raf)
    this.raf = null
  },

  tick() {
    const phase = this.el.dataset.phase
    const start = Number(this.el.dataset.start)
    const duration = Number(this.el.dataset.duration || 30000)

    if (phase !== "in_progress" || !start) {
      this.paint(0, 0, 1000)
      return
    }

    const serverNow = Date.now() - this.clockOffsetMs
    const elapsed = Math.max(0, serverNow - start)
    const remaining = Math.max(0, duration - elapsed)
    const progress = remaining / duration
    const seconds = Math.ceil(remaining / 1000)
    const score = Math.max(250, Math.round(1000 - 30 * Math.max(0, elapsed / 1000 - 5)))

    this.paint(progress, seconds, score)

    if (remaining > 0) {
      this.raf = requestAnimationFrame(this.tick)
    }
  },

  paint(progress, seconds, score) {
    const color = seconds <= 5 ? "#ef4444" : seconds <= 14 ? "#eab308" : "#22c55e"
    const radius = this.progress ? Number(this.progress.getAttribute("r") || 110) : 110
    const circumference = 2 * Math.PI * radius

    if (this.progress) {
      this.progress.style.stroke = color
      this.progress.style.strokeDasharray = `${circumference * progress} ${circumference}`
      this.progress.style.filter = `drop-shadow(0 0 6px ${color})`
      this.progress.style.opacity = progress > 0 ? "1" : "0"
    }

    if (this.timer) {
      this.timer.textContent = seconds
      this.timer.style.color = color
      this.timer.style.textShadow = `0 0 20px ${color}`
    }

    if (this.score) this.score.textContent = score.toLocaleString()

    if (this.shell) {
      this.shell.style.boxShadow =
        progress > 0
          ? `0 0 40px ${color}33, inset 0 0 30px rgba(0,0,0,0.5)`
          : "0 0 40px rgba(99,102,241,0.2), inset 0 0 30px rgba(0,0,0,0.5)"
    }
  },
}

Hooks.PodiumReveal = {
  mounted() {
    this.reveal()
  },

  updated() {
    this.reveal()
  },

  reveal() {
    this.el.querySelectorAll("[data-role='podium-row']").forEach(row => {
      const delay = Number(row.dataset.index || 0) * 600
      setTimeout(() => {
        row.classList.remove("translate-x-8", "opacity-0")
        row.classList.add("translate-x-0", "opacity-100")
      }, delay)
    })
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
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
