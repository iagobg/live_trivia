defmodule LiveTriviaWeb.AdminLive do
  use LiveTriviaWeb, :live_view

  alias LiveTrivia.Game
  alias LiveTrivia.Lobby
  alias LiveTrivia.PlayerColors
  alias LiveTriviaWeb.Presence
  alias LiveTriviaWeb.RoomPresence
  import LiveTriviaWeb.TriviaComponents

  @example_questions [
    %{
      question: "European capital",
      answer: "Paris",
      hints: [
        "Largest city in France",
        "Starts with P",
        "_ I _ A _",
        "City of Light",
        "Sounds like pair is"
      ]
    },
    %{
      question: "Biggest living land mammal",
      answer: "Elephant",
      hints: [
        "It is grey",
        "Starts with E",
        "A_E__E__",
        "Said to have great memory",
        "Has a trunk"
      ]
    },
    %{
      question: "Largest ocean",
      answer: "Pacific",
      hints: [
        "Covers more than 60 million square miles",
        "Starts with P",
        "P_C_I_IC",
        "Contains the Mariana Trench",
        "Not Atlantic"
      ]
    },
    %{
      question: "Smallest prime number",
      answer: "Two",
      hints: ["Only even prime", "Starts with T", "T_W_", "One less than three", "A number"]
    },
    %{
      question: "Chemical symbol for gold",
      answer: "Au",
      hints: ["From Latin aurum", "Starts with A", "A_", "Found in jewelry", "Value by weight"]
    },
    %{
      question: "Fastest land animal",
      answer: "Cheetah",
      hints: [
        "Runs over 70 mph",
        "Starts with C",
        "C_E_E_A_",
        "Spotted cat from Africa",
        "Not a leopard"
      ]
    },
    %{
      question: "Capital of Japan",
      answer: "Tokyo",
      hints: [
        "Home to the emperor",
        "Starts with T",
        "T_K_Y_",
        "Formerly Edo",
        "Known for cherry blossoms"
      ]
    },
    %{
      question: "Hardest natural substance",
      answer: "Diamond",
      hints: ["Made of carbon", "Starts with D", "D_A_O_N_", "Used in drills", "Often in rings"]
    },
    %{
      question: "Largest planet in our solar system",
      answer: "Jupiter",
      hints: [
        "Great Red Spot",
        "Starts with J",
        "J_P_T_R",
        "Fifth from the Sun",
        "Named after a Roman god"
      ]
    },
    %{
      question: "Most abundant gas in Earth's atmosphere",
      answer: "Nitrogen",
      hints: [
        "About 78 percent of air",
        "Starts with N",
        "N_T_O_E_",
        "Used in fertilizers",
        "Symbol N2"
      ]
    }
  ]
  @synthetic_player_count 16
  @synthetic_test_cycles 5
  @synthetic_keystroke_limit 18
  @synthetic_tick_ms 70
  @synthetic_submitted_clear_delay_ms 2_000

  def demo_questions, do: @example_questions

  @impl true
  def mount(%{"room_id" => room_id} = params, session, socket) do
    player_id = Map.fetch!(session, "player_id")
    room = Lobby.get_room(room_id)

    cond do
      is_nil(room) ->
        {:ok,
         socket
         |> put_flash(:error, "This room was closed.")
         |> push_navigate(to: ~p"/")}

      room.admin_id != player_id ->
        {:ok, push_navigate(socket, to: ~p"/rooms/#{room_id}")}

      true ->
        benchmark_auto_run? = params["benchmark"] == "synthetic"

        if connected?(socket) do
          Game.subscribe(room_id)
          RoomPresence.subscribe(room_id)
          RoomPresence.track_admin(room_id, player_id)
          Lobby.touch_room(room_id)

          if benchmark_auto_run? do
            Process.send_after(self(), :prepare_synthetic_benchmark, 300)
          end
        end

        socket =
          socket
          |> assign(:page_title, "Admin - #{room.name}")
          |> assign(:room, room)
          |> assign(:room_id, room_id)
          |> assign(:player_id, player_id)
          |> assign(:game_state, Game.get_state(room_id))
          |> assign(:players, RoomPresence.players(room_id))
          |> assign(:synthetic_players, [])
          |> assign(:synthetic_test_running?, benchmark_auto_run?)
          |> assign(:benchmark_auto_run?, benchmark_auto_run?)
          |> assign(:json_text, Jason.encode!(demo_questions(), pretty: true))
          |> assign(:validation_error, nil)

        {:ok, socket}
    end
  end

  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:room_id] && socket.assigns[:player_id] do
      untrack_synthetic_players(socket.assigns.room_id, socket.assigns[:synthetic_players] || [])

      Presence.untrack(
        self(),
        RoomPresence.admins_topic(socket.assigns.room_id),
        socket.assigns.player_id
      )

      Lobby.admin_left(socket.assigns.room_id)
    end

    :ok
  end

  @impl true
  def handle_event("load_demo", _params, socket) do
    Game.load_questions(socket.assigns.room_id, demo_questions())
    Lobby.touch_room(socket.assigns.room_id)
    {:noreply, assign(socket, :validation_error, nil)}
  end

  def handle_event("run_synthetic_render_test", _params, socket) do
    {:noreply, start_synthetic_test(socket, benchmark?: false)}
  end

  def handle_event("synthetic_submit", %{"cycle" => cycle}, socket) do
    cycle = parse_synthetic_cycle(cycle)
    {:noreply, broadcast_synthetic_submit(socket, socket.assigns.synthetic_players, cycle)}
  end

  def handle_event("synthetic_test_finished", params, socket) do
    emit_synthetic_client_summary(socket, params)
    {:noreply, assign(socket, :synthetic_test_running?, false)}
  end

  def handle_event("load_json", %{"quiz" => %{"json" => json}}, socket) do
    case decode_questions(json) do
      {:ok, questions} ->
        Game.load_questions(socket.assigns.room_id, questions)
        Lobby.touch_room(socket.assigns.room_id)

        {:noreply,
         socket
         |> assign(:json_text, json)
         |> assign(:validation_error, nil)}

      {:error, error} ->
        {:noreply, assign(socket, :validation_error, error)}
    end
  end

  def handle_event("start", _params, socket) do
    Game.start_quiz(socket.assigns.room_id)
    {:noreply, socket}
  end

  def handle_event("next", _params, socket) do
    Game.next_round(socket.assigns.room_id)
    {:noreply, socket}
  end

  def handle_event("reset", _params, socket) do
    Game.force_reset(socket.assigns.room_id)
    {:noreply, socket}
  end

  def handle_event("close_room", _params, socket) do
    Lobby.close_room(socket.assigns.room_id)

    {:noreply,
     socket
     |> put_flash(:info, "Room closed.")
     |> push_navigate(to: ~p"/")}
  end

  @impl true
  def handle_info(:prepare_synthetic_benchmark, socket) do
    if socket.assigns.benchmark_auto_run? do
      Game.load_questions(socket.assigns.room_id, demo_questions())
      Game.start_quiz(socket.assigns.room_id)
      Process.send_after(self(), :run_synthetic_benchmark, 300)
    end

    {:noreply, socket}
  end

  def handle_info(:run_synthetic_benchmark, socket) do
    if socket.assigns.benchmark_auto_run? do
      {:noreply, start_synthetic_test(socket, benchmark?: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:game_state, game_state}, socket) do
    {:noreply, assign(socket, :game_state, game_state)}
  end

  def handle_info({:room_closed, _room_id}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "This room was closed.")
     |> push_navigate(to: ~p"/")}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket),
    do: {:noreply, assign(socket, :players, RoomPresence.players(socket.assigns.room_id))}

  def handle_info({:synthetic_clear_submitted, player_id, bubble_id}, socket) do
    broadcast_synthetic_cleared(socket.assigns.room_id, player_id, bubble_id)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <%= if @game_state.phase == :podium do %>
        <.admin_header
          room={@room}
          game_state={@game_state}
          validation_error={@validation_error}
          synthetic_test_running?={@synthetic_test_running?}
        />
        <.podium game_state={@game_state} players={@players} />
      <% else %>
        <.admin_header
          room={@room}
          game_state={@game_state}
          validation_error={@validation_error}
          synthetic_test_running?={@synthetic_test_running?}
        />
        <.game_stage
          game_state={@game_state}
          players={@players}
          current_player_id={nil}
          room_id={@room_id}
        />
      <% end %>

      <div class="fixed bottom-4 right-4 z-50 w-[min(32rem,calc(100vw-2rem))] rounded-xl border border-gray-700 bg-gray-900/95 p-3 text-white shadow-2xl">
        <.form for={%{}} as={:quiz} phx-submit="load_json" class="space-y-2">
          <textarea
            name="quiz[json]"
            class="h-32 w-full rounded-lg border border-gray-700 bg-gray-950 p-3 font-mono text-xs text-gray-200 outline-none focus:border-indigo-500"
          >{@json_text}</textarea>
          <div class="flex items-center gap-2">
            <button
              type="submit"
              class="rounded-lg bg-indigo-700 px-3 py-1.5 text-sm font-semibold hover:bg-indigo-600"
            >
              Load JSON
            </button>
            <button
              type="button"
              phx-click="load_demo"
              class="rounded-lg bg-gray-700 px-3 py-1.5 text-sm hover:bg-gray-600"
            >
              Demo
            </button>
            <span :if={@validation_error} class="text-xs text-red-400">{@validation_error}</span>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  attr :game_state, :map, required: true
  attr :room, :map, required: true
  attr :validation_error, :string, default: nil
  attr :synthetic_test_running?, :boolean, default: false

  def admin_header(assigns) do
    ~H"""
    <div class="fixed left-0 right-0 top-0 z-50 border-b border-gray-700 bg-gray-900/95 px-4 py-2 text-white">
      <div class="flex flex-wrap items-center gap-3">
        <span class="mr-2 text-sm font-bold text-indigo-400">ADMIN</span>
        <span class="rounded-full bg-indigo-500/15 px-2 py-1 text-xs font-semibold text-indigo-200">
          {@room.name}
        </span>
        <span class="rounded-full bg-gray-700 px-2 py-1 text-xs font-medium text-gray-300">
          {@game_state.phase |> Atom.to_string() |> String.replace("_", " ") |> String.upcase()}
          <%= if @game_state.phase == :in_progress do %>
            - Q{@game_state.current_index + 1}/{length(@game_state.questions)}
          <% end %>
        </span>
        <div class="flex-1" />
        <button
          phx-click="run_synthetic_render_test"
          disabled={@synthetic_test_running?}
          class="rounded-lg bg-sky-800 px-3 py-1.5 text-sm font-medium hover:bg-sky-700 disabled:cursor-not-allowed disabled:opacity-30"
        >
          16-player test
        </button>
        <button
          phx-click="start"
          disabled={@game_state.phase != :loaded}
          class="rounded-lg bg-green-700 px-3 py-1.5 text-sm font-medium hover:bg-green-600 disabled:cursor-not-allowed disabled:opacity-30"
        >
          Start Quiz
        </button>
        <button
          phx-click="next"
          disabled={@game_state.phase not in [:in_progress, :results]}
          class="rounded-lg bg-yellow-700 px-3 py-1.5 text-sm font-medium hover:bg-yellow-600 disabled:cursor-not-allowed disabled:opacity-30"
        >
          Next Round
        </button>
        <button
          phx-click="reset"
          class="rounded-lg bg-red-800 px-3 py-1.5 text-sm font-medium hover:bg-red-700"
        >
          Force Reset
        </button>
        <button
          phx-click="close_room"
          data-confirm="Close this room?"
          class="rounded-lg bg-gray-800 px-3 py-1.5 text-sm font-medium hover:bg-gray-700"
        >
          Close Room
        </button>
      </div>
    </div>
    """
  end

  defp decode_questions(json) do
    with {:ok, decoded} <- Jason.decode(json),
         true <- is_list(decoded) || {:error, "JSON must be an array of questions"} do
      decoded
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, questions} ->
        case normalize_question(item, index) do
          {:ok, question} -> {:cont, {:ok, [question | questions]}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
      |> case do
        {:ok, questions} -> {:ok, Enum.reverse(questions)}
        error -> error
      end
    else
      {:error, %Jason.DecodeError{}} -> {:error, "Invalid JSON"}
      {:error, error} -> {:error, error}
    end
  end

  defp normalize_question(%{"question" => question, "answer" => answer} = item, _index) do
    hints =
      item
      |> Map.get("hints", [])
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.take(5)
      |> pad_hints()

    {:ok, %{question: to_string(question), answer: to_string(answer), hints: hints}}
  end

  defp normalize_question(_item, index),
    do: {:error, "Question #{index} is missing question or answer"}

  defp pad_hints(hints) do
    hints ++ Enum.map((length(hints) + 1)..5//1, &"Hint #{&1}")
  end

  defp start_synthetic_test(socket, opts) do
    synthetic_players = synthetic_players()
    untrack_synthetic_players(socket.assigns.room_id, socket.assigns.synthetic_players)
    track_synthetic_players(socket.assigns.room_id, synthetic_players)

    socket
    |> assign(:synthetic_players, synthetic_players)
    |> assign(:players, RoomPresence.players(socket.assigns.room_id))
    |> assign(:synthetic_test_running?, true)
    |> push_event("run_synthetic_typing_test", %{
      players: synthetic_players,
      guesses: synthetic_guesses(),
      cycles: @synthetic_test_cycles,
      tick_ms: @synthetic_tick_ms,
      keystroke_limit: @synthetic_keystroke_limit,
      benchmark: Keyword.get(opts, :benchmark?, false),
      room_id: socket.assigns.room_id
    })
  end

  defp emit_synthetic_client_summary(socket, params) when is_map(params) do
    if Map.get(params, "benchmark") do
      :telemetry.execute(
        [:live_trivia, :synthetic_benchmark, :client_summary],
        %{
          samples: parse_number(params["samples"], 0),
          avg_ms: parse_number(params["avg_ms"], 0.0),
          p50_ms: parse_number(params["p50_ms"], 0.0),
          p95_ms: parse_number(params["p95_ms"], 0.0),
          p99_ms: parse_number(params["p99_ms"], 0.0),
          max_ms: parse_number(params["max_ms"], 0.0),
          receive_p95_ms: parse_number(params["receive_p95_ms"], 0.0),
          receive_p99_ms: parse_number(params["receive_p99_ms"], 0.0),
          dom_p95_ms: parse_number(params["dom_p95_ms"], 0.0),
          dom_p99_ms: parse_number(params["dom_p99_ms"], 0.0),
          duration_ms: parse_number(params["duration_ms"], 0.0)
        },
        %{room_id: socket.assigns.room_id}
      )
    end
  end

  defp emit_synthetic_client_summary(_socket, _params), do: :ok

  defp parse_number(value, _default) when is_number(value), do: value

  defp parse_number(value, default) when is_binary(value) do
    case Float.parse(value) do
      {number, _rest} -> number
      :error -> default
    end
  end

  defp parse_number(_value, default), do: default

  defp synthetic_players do
    colors = PlayerColors.all()

    Enum.map(1..@synthetic_player_count, fn index ->
      %{
        player_id: "synthetic-#{index}",
        name: "Bot #{index}",
        color: Enum.at(colors, index - 1),
        joined_at: index
      }
    end)
  end

  defp track_synthetic_players(room_id, synthetic_players) do
    Enum.each(synthetic_players, fn player ->
      Presence.track(self(), RoomPresence.players_topic(room_id), player.player_id, player)
    end)
  end

  defp untrack_synthetic_players(_room_id, []), do: :ok

  defp untrack_synthetic_players(room_id, synthetic_players) do
    Enum.each(synthetic_players, fn player ->
      Presence.untrack(self(), RoomPresence.players_topic(room_id), player.player_id)
    end)
  end

  defp broadcast_synthetic_submit(socket, synthetic_players, cycle) do
    Enum.each(synthetic_players, fn player ->
      bubble_id = "synthetic-#{System.unique_integer([:positive, :monotonic])}"
      guess_text = synthetic_guess_text(player, cycle)

      Game.submit_guess(
        socket.assigns.room_id,
        player.player_id,
        player.name,
        guess_text
      )

      broadcast_synthetic_submitted(
        socket.assigns.room_id,
        player.player_id,
        guess_text,
        bubble_id
      )

      Process.send_after(
        self(),
        {:synthetic_clear_submitted, player.player_id, bubble_id},
        @synthetic_submitted_clear_delay_ms
      )
    end)

    socket
  end

  defp broadcast_synthetic_submitted(room_id, player_id, text, bubble_id) do
    LiveTriviaWeb.Endpoint.broadcast(
      RoomPresence.typing_topic(room_id),
      "guess_submitted",
      %{p: player_id, t: text, b: bubble_id}
    )
  end

  defp broadcast_synthetic_cleared(room_id, player_id, bubble_id) do
    LiveTriviaWeb.Endpoint.broadcast(
      RoomPresence.typing_topic(room_id),
      "guess_cleared",
      %{p: player_id, b: bubble_id}
    )
  end

  defp synthetic_guesses do
    [
      "montanha azul",
      "paises baixos distante",
      "paralelepipedo muito comprido",
      "cidade inventada",
      "elemento secreto",
      "capital escondida longe"
    ]
  end

  defp synthetic_guess_text(player, cycle) do
    guesses = synthetic_guesses()
    Enum.at(guesses, rem(cycle + synthetic_index(player), length(guesses)))
  end

  defp synthetic_index(%{player_id: "synthetic-" <> index}), do: String.to_integer(index)

  defp parse_synthetic_cycle(cycle) when is_integer(cycle), do: cycle

  defp parse_synthetic_cycle(cycle) when is_binary(cycle) do
    case Integer.parse(cycle) do
      {cycle, _rest} -> cycle
      :error -> 0
    end
  end

  defp parse_synthetic_cycle(_cycle), do: 0
end
