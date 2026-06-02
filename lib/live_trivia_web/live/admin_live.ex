defmodule LiveTriviaWeb.AdminLive do
  use LiveTriviaWeb, :live_view

  alias LiveTrivia.Game
  alias LiveTrivia.Lobby
  alias LiveTriviaWeb.Presence
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

  @impl true
  def mount(%{"room_id" => room_id}, session, socket) do
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
        if connected?(socket) do
          Game.subscribe(room_id)
          Phoenix.PubSub.subscribe(LiveTrivia.PubSub, players_topic(room_id))
          Phoenix.PubSub.subscribe(LiveTrivia.PubSub, room_topic(room_id))
          Phoenix.PubSub.subscribe(LiveTrivia.PubSub, typing_topic(room_id))
          track_admin(room_id, player_id)
          Lobby.touch_room(room_id)
        end

        socket =
          socket
          |> assign(:page_title, "Admin - #{room.name}")
          |> assign(:room, room)
          |> assign(:room_id, room_id)
          |> assign(:player_id, player_id)
          |> assign(:game_state, Game.get_state(room_id))
          |> assign(:players, players(room_id))
          |> assign(:typing_by_player, %{})
          |> assign(:guess_results, %{})
          |> assign(:json_text, Jason.encode!(@example_questions, pretty: true))
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
      Presence.untrack(self(), admin_topic(socket.assigns.room_id), socket.assigns.player_id)
      Lobby.admin_left(socket.assigns.room_id)
    end

    :ok
  end

  @impl true
  def handle_event("load_demo", _params, socket) do
    Game.load_questions(socket.assigns.room_id, @example_questions)
    Lobby.touch_room(socket.assigns.room_id)
    {:noreply, assign(socket, :validation_error, nil)}
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
  def handle_info({:game_state, game_state}, socket) do
    socket =
      if new_round?(socket.assigns.game_state, game_state) do
        socket
        |> assign(:typing_by_player, %{})
        |> assign(:guess_results, %{})
      else
        socket
      end

    {:noreply, assign(socket, :game_state, game_state)}
  end

  def handle_info({:room_closed, _room_id}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "This room was closed.")
     |> push_navigate(to: ~p"/")}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket),
    do: {:noreply, assign(socket, :players, players(socket.assigns.room_id))}

  def handle_info({:player_typing, player_id, text, guess_result}, socket) do
    {:noreply,
     socket
     |> assign(:typing_by_player, Map.put(socket.assigns.typing_by_player, player_id, text))
     |> assign(:guess_results, Map.put(socket.assigns.guess_results, player_id, guess_result))}
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
        />
        <.podium game_state={@game_state} players={@players} />
      <% else %>
        <.admin_header
          room={@room}
          game_state={@game_state}
          validation_error={@validation_error}
        />
        <.game_stage
          game_state={@game_state}
          players={@players}
          current_player_id={nil}
          typing_by_player={@typing_by_player}
          guess_results={@guess_results}
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

  defp players(room_id) do
    room_id
    |> players_topic()
    |> Presence.list()
    |> Enum.map(fn {player_id, %{metas: [meta | _]}} -> Map.put(meta, :player_id, player_id) end)
    |> Enum.sort_by(& &1.joined_at)
  end

  defp players_topic(room_id), do: "players:#{room_id}"
  defp room_topic(room_id), do: "room:#{room_id}"
  defp admin_topic(room_id), do: "admins:#{room_id}"
  defp typing_topic(room_id), do: "typing:#{room_id}"

  defp track_admin(room_id, player_id) do
    Presence.track(self(), admin_topic(room_id), player_id, %{
      admin_id: player_id,
      joined_at: System.system_time(:millisecond)
    })
  end

  defp new_round?(old_state, new_state) do
    old_state.current_index != new_state.current_index ||
      (old_state.phase != new_state.phase && new_state.phase == :in_progress)
  end
end
