# Live Trivia

Live Trivia is a Phoenix LiveView application for hosting real-time trivia rooms. An admin creates a room, loads a quiz, starts the rounds, and players join from their own devices to type guesses as the game state updates live.

The app is designed around fast server-authoritative state updates with minimal JavaScript. Elixir/Phoenix owns room lifecycle, presence, scoring, timers, and broadcasts; JavaScript is used for client ergonomics such as focus handling, viewport adjustments, timer animation, and visual polish.

## Features

- Create public or password-protected trivia rooms.
- Join as a player with a name and color.
- Host/admin screen for loading JSON questions, starting rounds, advancing rounds, resetting, and closing rooms.
- Server-side round timers, scheduled hints, scoring, closest-guess fallback, and final podium.
- Real-time player presence through Phoenix Presence and high-frequency typing bubbles through Phoenix Channels.
- Bounded in-memory room model suitable for live event/session style trivia games.
- Optional synthetic 16-player render test from the admin screen.

## Project Structure

Important application files:

- `lib/live_trivia/application.ex` starts PubSub, Presence, the game registry, the per-room supervisor, the lobby server, and the Phoenix endpoint.
- `lib/live_trivia/lobby.ex` owns room creation, room cleanup, room password verification, player capacity, color reservations, and public room summaries.
- `lib/live_trivia/game.ex` owns the authoritative quiz state for each room: loaded questions, round phase, timers, hints, guesses, scores, and podium state.
- `lib/live_trivia_web/live/lobby_live.ex` renders the room lobby and room creation form.
- `lib/live_trivia_web/live/admin_live.ex` renders the host/admin experience.
- `lib/live_trivia_web/live/player_live.ex` renders the player join and gameplay experience.
- `lib/live_trivia_web/room_presence.ex` centralizes room topics, player/admin/color presence, and player listing helpers.
- `lib/live_trivia_web/channels/typing_channel.ex` relays high-frequency typing events over Phoenix Channels without forcing LiveView re-renders.
- `lib/live_trivia_web/live/trivia_components.ex` contains shared UI components for the game stage, player orbit, mobile roster, hints, and podium.
- `assets/js/app.js` contains LiveView setup, the typing channel client, and hooks used for focus, viewport, timer, hint, and animation behavior.
- `assets/css/app.css` contains Tailwind CSS imports and custom styling.
- `priv/static/robots.txt` and `lib/live_trivia_web/components/layouts/root.html.heex` contain basic SEO/static document metadata.

## Requirements

For local development:

- Elixir and Erlang/OTP compatible with `mix.exs`.
- Mix, Hex, and Rebar.
- Docker, only if you want to build and run the container image.

The project does not require a database for its current in-memory room/game model.

## Running Locally

Install dependencies and build local assets:

```sh
mix setup
```

Start the Phoenix development server:

```sh
mix phx.server
```

Or run it inside IEx:

```sh
iex -S mix phx.server
```

Open the app at:

```text
http://localhost:3070
```

Useful local commands:

```sh
mix test
mix format
mix precommit
```

`mix precommit` is the project check used before finishing changes. It compiles with warnings as errors, checks for unused dependencies, formats, and runs the test suite.

## Synthetic Benchmarking

Run the benchmark launch routine:

```sh
scripts/benchmark_synthetic.sh
```

Use `BENCHMARK_LABEL` to tag comparable runs:

```sh
BENCHMARK_LABEL=json_channels scripts/benchmark_synthetic.sh
```

The launcher writes each run to `benchmark_logs/<timestamp>_<label>.log`. It waits for the server to become ready, waits `BENCHMARK_WARMUP_SECONDS` seconds, and then opens the benchmark route. The default warmup is 3 seconds; use the same value for comparable runs:

```sh
BENCHMARK_LABEL=json_channels BENCHMARK_WARMUP_SECONDS=5 scripts/benchmark_synthetic.sh
```

This starts Phoenix with `LIVE_TRIVIA_BENCHMARK=1`, opens `/benchmark/synthetic`, creates a benchmark room, loads the demo quiz, starts the round, and auto-runs the 16-player synthetic websocket test.

Benchmark output is split between:

- Browser console: client render latency summary for synthetic typing updates (`avg`, `p50`, `p95`, `p99`, `max`).
- Server logs: 5-second benchmark snapshots with typing message count/rate, payload bytes, average/p95/max channel handling time, BEAM reductions, BEAM memory, Linux RSS, Linux process CPU, process count, and run queue.
- Server logs: one end-of-run `benchmark attempt summary` combining client latency with aggregate typing count/rate, payload bytes, handler timing, reductions, average/max CPU, max RSS/BEAM memory, max run queue, and snapshot count.

You can also start the app manually with telemetry enabled:

```sh
LIVE_TRIVIA_BENCHMARK=1 LIVE_TRIVIA_BENCHMARK_LABEL=json_channels mix phx.server
```

Then open:

```text
http://localhost:3070/benchmark/synthetic
```

## Quiz JSON Format

The admin screen accepts a JSON array of questions. Each item needs a `question` and `answer`; `hints` is optional and will be padded to five hints when fewer are provided.

```json
[
  {
    "question": "European capital",
    "answer": "Paris",
    "hints": [
      "Largest city in France",
      "Starts with P",
      "_ I _ A _",
      "City of Light",
      "Sounds like pair is"
    ]
  }
]
```

## Running With Docker

Build the image:

```sh
docker build -t live-trivia .
```

Generate a production secret if you do not already have one:

```sh
mix phx.gen.secret
```

Run the container locally:

```sh
docker run --rm \
  --name live-trivia \
  -p 3070:3070 \
  -e SECRET_KEY_BASE="replace-with-a-generated-secret" \
  -e PHX_HOST="localhost" \
  live-trivia
```

Then open:

```text
http://localhost:3070
```

For a deployed host, set `PHX_HOST` to the public hostname instead:

```sh
docker run -d \
  --name live-trivia \
  -p 3070:3070 \
  -e SECRET_KEY_BASE="replace-with-a-generated-secret" \
  -e PHX_HOST="trivia.example.com" \
  live-trivia
```

The Dockerfile sets `PHX_SERVER=true` and `PORT=3070` by default. You can override the port if needed:

```sh
docker run --rm \
  -p 4000:4000 \
  -e PORT=4000 \
  -e SECRET_KEY_BASE="replace-with-a-generated-secret" \
  -e PHX_HOST="localhost" \
  live-trivia
```

## Runtime Environment Variables

- `SECRET_KEY_BASE`: required in production/Docker releases. Generate with `mix phx.gen.secret`.
- `PHX_HOST`: public hostname used by Phoenix URL generation in production. Defaults to `example.com` if not set, but you should set it for Docker/deployments.
- `PORT`: HTTP port. Defaults to `3070`.
- `PHX_SERVER`: enables the Phoenix server in releases. The Dockerfile sets this to `true`.
- `TYPING_BUBBLE_ANIMATION`: set to `false` to disable submitted typing-bubble burst animation.
- `DNS_CLUSTER_QUERY`: optional DNS clustering query used by Phoenix/DNSCluster in production.

## Notes On Architecture

Rooms and games are intentionally in memory. This keeps the live event flow simple and fast, but it also means rooms do not survive application restarts. The current limits are conservative: up to 16 rooms and 16 players per room.

For the intended use case, Phoenix LiveView and Elixir handle the real-time coordination well: each game room has a dedicated `LiveTrivia.Game` process, room membership uses Presence, and authoritative state changes fan out over PubSub. High-frequency typing bubbles use Phoenix Channels and client-side rendering so they do not force LiveView diffs, while the browser-side JavaScript remains focused on presentation details rather than game authority.

## Known Issues / Future Improvements

- The current tuning in throttling/flush rate is geared towards high responsiveness, however CPU usage is still too high for real world prod. While the text bubble payloads are currently quite small, there's room for improvement. The next step is probably doing binary payloads to streamline the data even further and skip JSON enconding/decoding. That is still unlikely to bring performance to manageable levels for a high amount of users, but that can be remedied by altering the throttle and flush windows.
- Currently on smaller vertical desktop resolutions, the players directly below the main orbit will have their text bubble eclipsed by it.
- Empty space characters create a differently sized typing bubble.