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
const channelSocket = new Socket("/socket", {})
let channelSocketConnected = false
const TYPING_PUSH_THROTTLE_MS = 100
const SYNTHETIC_CHANNEL_JOIN_TIMEOUT_MS = 30000
const SYNTHETIC_CONNECT_BATCH_SIZE = 4
const SYNTHETIC_CONNECT_BATCH_DELAY_MS = 150

const ensureChannelSocket = () => {
  if (!channelSocketConnected) {
    channelSocket.connect()
    channelSocketConnected = true
  }

  return channelSocket
}

const typingBubbleStyle = player =>
  `border-color: ${player.color}aa; background-color: ${player.color}dd; box-shadow: 0 0 18px ${player.color}66;`

const normalizeTypingPayload = payload => ({
  player_slot: payload.i ?? payload.player_slot ?? payload.playerSlot ?? null,
  player_id: payload.p || payload.player_id || payload.playerId || "",
  text: payload.t || payload.text || "",
  timestamp: payload.ts || null,
})

const normalizeSubmittedPayload = payload => ({
  player_slot: payload.i ?? payload.player_slot ?? payload.playerSlot ?? null,
  player_id: payload.p || payload.player_id || payload.playerId || "",
  text: payload.t || payload.text || "",
  bubble_id: payload.b || payload.bubble_id || payload.bubbleId || null,
})

const normalizeClearedPayload = payload => ({
  player_slot: payload.i ?? payload.player_slot ?? payload.playerSlot ?? null,
  player_id: payload.p || payload.player_id || payload.playerId || "",
  bubble_id: payload.b || payload.bubble_id || payload.bubbleId || null,
})

const compactPayload = payload =>
  Object.fromEntries(Object.entries(payload).filter(([_key, value]) => value !== null && value !== undefined))


const percentile = (sortedValues, percentileValue) => {
  if (sortedValues.length === 0) return 0

  const index = Math.min(
    sortedValues.length - 1,
    Math.max(0, Math.ceil(sortedValues.length * percentileValue) - 1)
  )

  return sortedValues[index]
}

const roundMetric = value => Math.round(value * 100) / 100

const measureTypingBubble = bubble => {
  const content = bubble.querySelector(".typing-bubble-content")
  if (!content) return

  bubble.classList.remove("is-overflowing")

  requestAnimationFrame(() => {
    const styles = window.getComputedStyle(bubble)
    const horizontalPadding = parseFloat(styles.paddingLeft) + parseFloat(styles.paddingRight)
    const availableWidth = bubble.clientWidth - horizontalPadding
    const overflow = content.scrollWidth - availableWidth

    if (overflow > 4) bubble.classList.add("is-overflowing")
  })
}


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


Hooks.TypingChannel = {
  mounted() {
    this.players = new Map()
    this.playersBySlot = new Map()
    this.channel = null
    this.handleInput = this.handleInput.bind(this)
    this.handleTyping = this.handleTyping.bind(this)
    this.handleGuessSubmitted = this.handleGuessSubmitted.bind(this)
    this.handleGuessCleared = this.handleGuessCleared.bind(this)
    this.flushTypingPush = this.flushTypingPush.bind(this)
    this.syntheticTimer = null
    this.syntheticSlotTimer = null
    this.syntheticConnections = []
    this.syntheticRunId = 0
    this.benchmarkRun = null
    this.pendingTypingPayload = null
    this.pendingTypingTimer = null
    this.lastLocalTypingText = null
    this.lastSentTypingText = null
    this.lastTypingPushAt = 0
    this.channelJoined = false
    this.channelJoin = null

    this.cachePlayers()
    this.connectChannel()
    this.handleEvent("run_synthetic_typing_test", config => this.runSyntheticTypingTest(config))
    this.el.addEventListener("input", this.handleInput)
  },

  updated() {
    this.cachePlayers()
  },

  destroyed() {
    this.el.removeEventListener("input", this.handleInput)

    if (this.syntheticTimer) clearTimeout(this.syntheticTimer)
    if (this.syntheticSlotTimer) clearTimeout(this.syntheticSlotTimer)
    if (this.pendingTypingTimer) clearTimeout(this.pendingTypingTimer)
    this.disconnectSyntheticPlayers()

    if (this.channel) {
      this.channel.leave()
      this.channel = null
    }
  },

  connectChannel() {
    const roomId = this.el.dataset.roomId
    const typingTopic = this.el.dataset.typingTopic || `t:${roomId}`
    if (!roomId) return

    this.channel = ensureChannelSocket().channel(typingTopic, {})
    this.channelJoined = false
    this.channel.on("t", this.handleTyping)
    this.channel.on("s", this.handleGuessSubmitted)
    this.channel.on("c", this.handleGuessCleared)
    this.channel.on("typing", this.handleTyping)
    this.channel.on("guess_submitted", this.handleGuessSubmitted)
    this.channel.on("guess_cleared", this.handleGuessCleared)
    this.channelJoin = new Promise((resolve, reject) => {
      this.channel
        .join()
        .receive("ok", () => {
          this.channelJoined = true
          resolve()
          this.flushTypingPush()
        })
        .receive("error", reject)
        .receive("timeout", () => reject(new Error("typing channel join timed out")))
    })
  },

  cachePlayers() {
    const players = new Map()
    const playersBySlot = new Map()

    this.el.querySelectorAll("[data-role='typing-slot'][data-player-id]").forEach(slot => {
      const playerId = slot.dataset.playerId
      const playerSlot = Number(slot.dataset.playerSlot)
      const player = players.get(playerId) || {
        player_id: playerId,
        player_slot: Number.isInteger(playerSlot) ? playerSlot : null,
        name: slot.dataset.playerName || "",
        color: slot.dataset.playerColor || "#888888",
        slots: [],
      }

      player.slots.push(slot)
      players.set(playerId, player)

      if (Number.isInteger(player.player_slot)) {
        playersBySlot.set(player.player_slot, player)
      }
    })

    this.players = players
    this.playersBySlot = playersBySlot
  },

  handleInput(event) {
    const input = event.target.closest?.("input[name='guess[text]']")
    const playerId = this.el.dataset.currentPlayerId

    if (!input || !playerId || !this.channel) return

    const player = this.players.get(playerId)
    const text = input.value.slice(0, 80)
    const payload = Number.isInteger(player?.player_slot) ? {i: player.player_slot, t: text} : {p: playerId, t: text}

    if (payload.t !== this.lastLocalTypingText) {
      this.lastLocalTypingText = payload.t
      this.handleTyping(player ? payload : {p: playerId, t: payload.t})
    }

    this.queueTypingPush(payload)
  },

  queueTypingPush(payload) {
    if (!this.channel) return

    if (payload.t === this.lastSentTypingText) {
      this.pendingTypingPayload = null

      if (this.pendingTypingTimer) {
        clearTimeout(this.pendingTypingTimer)
        this.pendingTypingTimer = null
      }

      return
    }

    if (payload.t === "") {
      if (this.pendingTypingTimer) {
        clearTimeout(this.pendingTypingTimer)
        this.pendingTypingTimer = null
      }

      this.sendTypingPayload(payload)
      return
    }

    const now = performance.now()
    const remainingMs = TYPING_PUSH_THROTTLE_MS - (now - this.lastTypingPushAt)

    if (remainingMs <= 0) {
      this.sendTypingPayload(payload)
      return
    }

    this.pendingTypingPayload = payload

    if (!this.pendingTypingTimer) {
      this.pendingTypingTimer = setTimeout(this.flushTypingPush, remainingMs)
    }
  },

  flushTypingPush() {
    this.pendingTypingTimer = null

    if (!this.pendingTypingPayload || !this.channelJoined) return

    this.sendTypingPayload(this.pendingTypingPayload)
  },

  sendTypingPayload(payload) {
    if (!this.channel || payload.t === this.lastSentTypingText) return
    if (!this.channelJoined) {
      this.pendingTypingPayload = payload
      return
    }

    this.channel.push("t", compactPayload(payload))
    this.lastSentTypingText = payload.t
    this.lastTypingPushAt = performance.now()
    this.pendingTypingPayload = null
  },

  handleTyping(payload) {
    const update = normalizeTypingPayload(payload)
    const player = this.playerForUpdate(update)

    if (!player) return

    const receivedAt = performance.now()
    player.slots.forEach(slot => this.setLiveBubble(slot, player, update.text))
    this.recordBenchmarkLatency(update, receivedAt)
  },

  handleGuessSubmitted(payload) {
    const update = normalizeSubmittedPayload(payload)
    const player = this.playerForUpdate(update)

    if (!player) return

    player.slots.forEach(slot => {
      this.removeLiveBubble(slot)
      this.addSubmittedBubble(slot, player, update)
    })
  },

  handleGuessCleared(payload) {
    const update = normalizeClearedPayload(payload)
    const player = this.playerForUpdate(update)

    if (!player) return

    player.slots.forEach(slot => this.removeSubmittedBubble(slot, update.bubble_id))
  },

  setLiveBubble(slot, player, text) {
    let bubble = slot.querySelector("[data-role='live-typing-bubble']")

    if (!text) {
      if (bubble) bubble.remove()
      return
    }

    if (!bubble) {
      bubble = document.createElement("div")
      bubble.dataset.role = "live-typing-bubble"
      bubble.className = this.liveBubbleClass(slot)
      bubble.style.cssText = typingBubbleStyle(player)

      const content = document.createElement("span")
      content.className = "typing-bubble-content"
      bubble.appendChild(content)
      slot.appendChild(bubble)
    }

    bubble.querySelector(".typing-bubble-content").textContent = text
    measureTypingBubble(bubble)
  },

  removeLiveBubble(slot) {
    slot.querySelector("[data-role='live-typing-bubble']")?.remove()
  },

  playerForUpdate(update) {
    const slot = Number(update.player_slot)

    if (Number.isInteger(slot) && this.playersBySlot.has(slot)) {
      return this.playersBySlot.get(slot)
    }

    return this.players.get(update.player_id)
  },

  addSubmittedBubble(slot, player, update) {
    const bubble = document.createElement("div")
    const bubbleId = update.bubble_id || `${Date.now()}-${Math.random()}`

    bubble.dataset.role = "submitted-typing-bubble"
    bubble.dataset.bubbleId = bubbleId
    bubble.className = this.submittedBubbleClass(slot)
    bubble.style.cssText = typingBubbleStyle(player)

    const content = document.createElement("span")
    content.className = "guess-burst-content"
    content.textContent = update.text
    bubble.appendChild(content)
    slot.appendChild(bubble)

    // Force animation restart even when the same player submits repeatedly in quick succession.
    bubble.style.animation = "none"
    void bubble.offsetWidth
    bubble.style.removeProperty("animation")

    setTimeout(() => bubble.remove(), 1200)
  },

  async runSyntheticTypingTest(config) {
    if (!this.channel) {
      console.warn("Synthetic typing test skipped: typing channel is not connected")
      this.pushEvent("synthetic_test_finished", {error: "typing_channel_not_connected"})
      return
    }
    if (this.syntheticTimer) clearTimeout(this.syntheticTimer)
    if (this.syntheticSlotTimer) clearTimeout(this.syntheticSlotTimer)
    this.disconnectSyntheticPlayers()

    const roomId = this.el.dataset.roomId
    const typingTopic = this.el.dataset.typingTopic || `t:${roomId}`
    const players = config.players || []
    const cycles = Number(config.cycles || 1)
    const tickMs = Number(config.tick_ms || 70)
    const keystrokeLimit = Number(config.keystroke_limit || 18)
    const guesses = config.guesses || []
    const benchmark = config.benchmark === true
    const roomIdForBenchmark = config.room_id || roomId
    const runId = this.syntheticRunId + 1

    this.syntheticRunId = runId
    this.benchmarkRun = benchmark ? this.newBenchmarkRun(roomIdForBenchmark) : null
    this.cachePlayers()

    let connections = []

    try {
      await this.waitForTypingChannel(runId)
      await this.waitForSyntheticPlayerSlots(players, runId)

      if (this.syntheticRunId !== runId) return

      await this.connectSyntheticPlayers(typingTopic, players, runId, connections)
    } catch (error) {
      console.warn("Synthetic typing test failed to start", error)
      this.disconnectSyntheticPlayers(connections)

      if (this.syntheticRunId === runId) {
        this.pushEvent("synthetic_test_finished", {
          error: error?.message || "synthetic_start_failed",
        })
      }

      return
    }

    if (this.syntheticRunId !== runId) {
      this.disconnectSyntheticPlayers(connections)
      return
    }

    this.syntheticConnections = connections

    this.runSyntheticCycle({
      players,
      cycles,
      tickMs,
      keystrokeLimit,
      guesses,
      cycle: 0,
      keystroke: 0,
      runId,
    })
  },

  async connectSyntheticPlayers(typingTopic, players, runId, connections) {
    for (let index = 0; index < players.length; index += SYNTHETIC_CONNECT_BATCH_SIZE) {
      if (this.syntheticRunId !== runId) throw new Error("synthetic run cancelled")

      const batch = players.slice(index, index + SYNTHETIC_CONNECT_BATCH_SIZE)
      const batchConnections = await Promise.all(
        batch.map(player => this.connectSyntheticPlayer(typingTopic, player))
      )

      connections.push(...batchConnections)

      if (
        index + SYNTHETIC_CONNECT_BATCH_SIZE < players.length &&
        this.syntheticRunId === runId
      ) {
        await this.waitForSyntheticConnectBatchDelay(runId)
      }
    }
  },

  connectSyntheticPlayer(typingTopic, player) {
    return new Promise((resolve, reject) => {
      const socket = new Socket("/socket", {params: {synthetic_player_id: player.player_id}})
      const channel = socket.channel(typingTopic, {})

      socket.connect()

      channel
        .join(SYNTHETIC_CHANNEL_JOIN_TIMEOUT_MS)
        .receive("ok", () => resolve({player, socket, channel}))
        .receive("error", error => {
          socket.disconnect()
          reject(error)
        })
        .receive("timeout", () => {
          socket.disconnect()
          reject(new Error("synthetic channel join timed out"))
        })
    })
  },

  waitForSyntheticConnectBatchDelay(runId) {
    return new Promise((resolve, reject) => {
      this.syntheticSlotTimer = setTimeout(() => {
        if (this.syntheticRunId === runId) {
          resolve()
        } else {
          reject(new Error("synthetic run cancelled"))
        }
      }, SYNTHETIC_CONNECT_BATCH_DELAY_MS)
    })
  },

  async waitForTypingChannel(runId) {
    if (this.channelJoined) return
    if (!this.channelJoin) throw new Error("typing channel is not connected")

    await this.channelJoin

    if (this.syntheticRunId !== runId) {
      throw new Error("synthetic run cancelled")
    }
  },

  waitForSyntheticPlayerSlots(players, runId) {
    const requiredPlayerIds = new Set(players.map(player => player.player_id))
    const startedAt = performance.now()
    const timeoutMs = 15000

    return new Promise((resolve, reject) => {
      const check = () => {
        if (this.syntheticRunId !== runId) {
          reject(new Error("synthetic run cancelled"))
          return
        }

        this.cachePlayers()

        const allSlotsReady = [...requiredPlayerIds].every(playerId => this.players.has(playerId))

        if (allSlotsReady) {
          resolve()
          return
        }

        if (performance.now() - startedAt >= timeoutMs) {
          reject(new Error("synthetic player slots timed out"))
          return
        }

        this.syntheticSlotTimer = setTimeout(check, 50)
      }

      check()
    })
  },

  disconnectSyntheticPlayers(connections = this.syntheticConnections) {
    connections.forEach(({channel, socket}) => {
      channel.leave()
      socket.disconnect()
    })

    if (connections === this.syntheticConnections) {
      this.syntheticConnections = []
    }
  },

  runSyntheticCycle(state) {
    if (this.syntheticRunId !== state.runId) return

    const maxKeystrokes = this.syntheticCycleKeystrokes(state)

    if (state.keystroke <= maxKeystrokes) {
      state.players.forEach(player => {
        const text = this.syntheticKeystrokeText(player, state.cycle, state.keystroke, state.guesses)
        this.pushSyntheticTyping(player, text)
      })

      this.syntheticTimer = setTimeout(
        () => this.runSyntheticCycle({...state, keystroke: state.keystroke + 1}),
        state.tickMs
      )

      return
    }

    this.pushEvent("synthetic_submit", {cycle: state.cycle})

    const nextCycle = state.cycle + 1

    if (nextCycle >= state.cycles) {
      this.syntheticTimer = setTimeout(() => {
        this.disconnectSyntheticPlayers()
        this.pushEvent("synthetic_test_finished", this.finishBenchmarkRun())
      }, 300)
      return
    }

    this.syntheticTimer = setTimeout(
      () => this.runSyntheticCycle({...state, cycle: nextCycle, keystroke: 1}),
      Math.max(300, state.tickMs)
    )
  },

  pushSyntheticTyping(player, text) {
    const connection = this.syntheticConnections.find(
      ({player: syntheticPlayer}) => syntheticPlayer.player_id === player.player_id
    )

    if (!connection) return

    const payload = {i: this.syntheticIndex(player) - 1, t: text}

    if (this.benchmarkRun) payload.ts = performance.now()

    connection.channel.push("t", payload)
  },

  newBenchmarkRun(roomId) {
    return {roomId, startedAt: performance.now(), latencies: [], receiveLatencies: [], domLatencies: []}
  },

  recordBenchmarkLatency(update, receivedAt) {
    if (!this.benchmarkRun || typeof update.timestamp !== "number") return

    const renderedAt = performance.now()
    this.benchmarkRun.latencies.push(renderedAt - update.timestamp)
    this.benchmarkRun.receiveLatencies.push(receivedAt - update.timestamp)
    this.benchmarkRun.domLatencies.push(renderedAt - receivedAt)
  },

  finishBenchmarkRun() {
    if (!this.benchmarkRun) return {}

    const run = this.benchmarkRun
    const sorted = [...run.latencies].sort((a, b) => a - b)
    const sortedReceive = [...run.receiveLatencies].sort((a, b) => a - b)
    const sortedDom = [...run.domLatencies].sort((a, b) => a - b)
    const samples = sorted.length
    const summary = {
      benchmark: true,
      room_id: run.roomId,
      samples,
      avg_ms: roundMetric(samples ? sorted.reduce((sum, value) => sum + value, 0) / samples : 0),
      p50_ms: roundMetric(percentile(sorted, 0.5)),
      p95_ms: roundMetric(percentile(sorted, 0.95)),
      p99_ms: roundMetric(percentile(sorted, 0.99)),
      max_ms: roundMetric(samples ? sorted[samples - 1] : 0),
      receive_p95_ms: roundMetric(percentile(sortedReceive, 0.95)),
      receive_p99_ms: roundMetric(percentile(sortedReceive, 0.99)),
      dom_p95_ms: roundMetric(percentile(sortedDom, 0.95)),
      dom_p99_ms: roundMetric(percentile(sortedDom, 0.99)),
      duration_ms: roundMetric(performance.now() - run.startedAt),
    }

    console.table([summary])
    this.benchmarkRun = null

    return summary
  },

  syntheticCycleKeystrokes({players, cycle, guesses, keystrokeLimit}) {
    const maxLength = players.reduce((max, player) => {
      return Math.max(max, this.syntheticGuessText(player, cycle, guesses).length)
    }, keystrokeLimit)

    return Math.min(maxLength, keystrokeLimit)
  },

  syntheticKeystrokeText(player, cycle, keystroke, guesses) {
    const text = this.syntheticGuessText(player, cycle, guesses)
    const visibleLength = Math.min(
      text.length,
      Math.max(1, keystroke - ((this.syntheticIndex(player) + cycle) % 4))
    )

    return text.slice(0, visibleLength)
  },

  syntheticGuessText(player, cycle, guesses) {
    if (guesses.length === 0) return ""
    return guesses[(cycle + this.syntheticIndex(player)) % guesses.length]
  },

  syntheticIndex(player) {
    const match = String(player.player_id || "").match(/synthetic-(\d+)/)
    return match ? Number(match[1]) : 0
  },

  removeSubmittedBubble(slot, bubbleId) {
    if (!bubbleId) return

    slot
      .querySelectorAll(`[data-role='submitted-typing-bubble'][data-bubble-id='${CSS.escape(bubbleId)}']`)
      .forEach(bubble => bubble.remove())
  },

  liveBubbleClass(slot) {
    if (slot.dataset.variant === "mobile") {
      return "typing-bubble is-live absolute left-0 top-0 z-[60] w-full max-w-full translate-y-0 overflow-hidden rounded-full border px-2.5 py-1.5 text-center text-[0.68rem] font-bold text-white opacity-100 shadow-lg"
    }

    return "typing-bubble is-live absolute left-0 top-0 z-[60] w-32 max-w-32 translate-y-0 overflow-hidden rounded-full border px-2 py-1 text-xs font-semibold text-white opacity-100 shadow-lg"
  },

  submittedBubbleClass(slot) {
    if (slot.dataset.variant === "mobile") {
      return "guess-burst pointer-events-none absolute inset-x-0 top-0 z-[80] w-full overflow-hidden rounded-full border px-2 py-1 text-center text-[0.68rem] font-semibold text-white opacity-0 shadow-lg"
    }

    return "guess-burst pointer-events-none absolute inset-x-0 top-0 z-[80] w-32 overflow-hidden rounded-full border px-2 py-1 text-center text-xs font-semibold text-white opacity-0 shadow-lg"
  },
}

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
