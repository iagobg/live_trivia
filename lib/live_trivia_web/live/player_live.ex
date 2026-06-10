defmodule LiveTriviaWeb.PlayerLive do
  use LiveTriviaWeb, :live_view

  alias LiveTrivia.Game
  alias LiveTrivia.Lobby
  alias LiveTrivia.PlayerColors
  alias LiveTriviaWeb.Presence
  alias LiveTriviaWeb.TypingBubble
  import LiveTriviaWeb.TriviaComponents

  @submitted_clear_delay_ms 2_000
  @typing_flush_ms 33

  @impl true
  def mount(%{"room_id" => room_id}, session, socket) do
    player_id = Map.fetch!(session, "player_id")
    player_color = Map.fetch!(session, "player_color")
    room = Lobby.get_room(room_id)
    game_state = room && Game.get_state(room_id)
    joinable = game_state && joinable?(game_state)
    room_password_required? = room && not is_nil(room.password_hash)
    room_unlocked? = !room_password_required?

    reservation =
      reserve_player_slot(socket, room, joinable && room_unlocked?, room_id, player_id)

    if connected?(socket) && room do
      Game.subscribe(room_id)
      Phoenix.PubSub.subscribe(LiveTrivia.PubSub, players_topic(room_id))
      Phoenix.PubSub.subscribe(LiveTrivia.PubSub, room_topic(room_id))
      Phoenix.PubSub.subscribe(LiveTrivia.PubSub, typing_topic(room_id))
      Lobby.touch_room(room_id)
    end

    candidate_color = initial_color(room_id, player_id, player_color)

    if connected?(socket) && room && joinable && room_unlocked? && reservation == :ok do
      Phoenix.PubSub.subscribe(LiveTrivia.PubSub, color_topic(room_id))
      track_color_selection(room_id, player_id, candidate_color)
    end

    socket =
      socket
      |> assign(:page_title, (room && room.name) || "Closed Room")
      |> assign(:room, room)
      |> assign(:room_id, room_id)
      |> assign(:game_state, game_state)
      |> assign(:joinable, joinable)
      |> assign(:room_password_required?, room_password_required?)
      |> assign(:room_unlocked?, room_unlocked?)
      |> assign(:room_password_error, nil)
      |> assign(:players, if(room && room_unlocked?, do: players(room_id), else: []))
      |> assign(:player_id, player_id)
      |> assign(:player_color, player_color)
      |> assign(:candidate_color, candidate_color)
      |> assign(:player_colors, PlayerColors.all())
      |> assign(
        :taken_colors,
        if(room && room_unlocked?, do: taken_colors(room_id, player_id), else: [])
      )
      |> assign(:player_name, nil)
      |> assign(:input_text, "")
      |> assign(:guess_result, nil)
      |> assign(:typing_by_player, %{})
      |> assign(:guess_results, %{})
      |> assign(:previous_round, nil)

    cond do
      is_nil(room) ->
        {:ok,
         socket
         |> put_flash(:error, "This room was closed.")
         |> push_navigate(to: ~p"/")}

      !joinable ->
        {:ok,
         socket
         |> put_flash(:error, "This game is already in progress.")
         |> push_navigate(to: ~p"/")}

      reservation == {:error, :room_full} ->
        {:ok,
         socket
         |> put_flash(:error, "This room is full.")
         |> push_navigate(to: ~p"/")}

      reservation == {:error, :game_in_progress} ->
        {:ok,
         socket
         |> put_flash(:error, "This game is already in progress.")
         |> push_navigate(to: ~p"/")}

      reservation == {:error, :room_closed} ->
        {:ok,
         socket
         |> put_flash(:error, "This room was closed.")
         |> push_navigate(to: ~p"/")}

      true ->
        {:ok, socket}
    end
  end

  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:room_id] && socket.assigns[:player_id] do
      Lobby.leave_room(socket.assigns.room_id, socket.assigns.player_id)
      Lobby.touch_room(socket.assigns.room_id)
    end

    :ok
  end

  @impl true
  def handle_event("join", %{"player" => %{"name" => name}}, socket) do
    name = name |> String.trim() |> String.slice(0, 20)

    cond do
      name == "" ->
        {:noreply, socket}

      !joinable?(socket.assigns.game_state) ->
        {:noreply,
         socket
         |> put_flash(:error, "This game is already in progress.")
         |> push_navigate(to: ~p"/")}

      true ->
        color = socket.assigns.candidate_color

        join_player(socket, name, color)
    end
  end

  def handle_event("choose_color", %{"color" => color}, socket) do
    cond do
      socket.assigns.player_name ->
        {:noreply, socket}

      !PlayerColors.valid?(color) ->
        {:noreply, socket}

      color in taken_colors(socket.assigns.room_id, socket.assigns.player_id) ->
        {:noreply,
         socket
         |> assign(:taken_colors, taken_colors(socket.assigns.room_id, socket.assigns.player_id))}

      true ->
        update_color_selection(socket, color)

        {:noreply,
         socket
         |> assign(:candidate_color, color)
         |> assign(:taken_colors, taken_colors(socket.assigns.room_id, socket.assigns.player_id))}
    end
  end

  def handle_event("unlock_room", %{"room" => %{"password" => password}}, socket) do
    case Lobby.verify_room_password(socket.assigns.room_id, password) do
      :ok ->
        unlock_room(socket)

      {:error, :invalid_password} ->
        {:noreply, assign(socket, :room_password_error, "Incorrect password.")}

      {:error, :room_closed} ->
        {:noreply,
         socket
         |> put_flash(:error, "This room was closed.")
         |> push_navigate(to: ~p"/")}
    end
  end

  def handle_event("leave_room", _params, socket) do
    if socket.assigns.player_name do
      Presence.untrack(self(), players_topic(socket.assigns.room_id), socket.assigns.player_id)
    else
      Presence.untrack(self(), color_topic(socket.assigns.room_id), socket.assigns.player_id)
    end

    Lobby.leave_room(socket.assigns.room_id, socket.assigns.player_id)
    Lobby.touch_room(socket.assigns.room_id)

    {:noreply,
     socket
     |> put_flash(:info, "You left the room.")
     |> push_navigate(to: ~p"/")}
  end

  def handle_event("typing", %{"guess" => %{"text" => text}}, socket) do
    text = String.slice(text, 0, 80)

    socket =
      if socket.assigns.player_name do
        typing_by_player =
          TypingBubble.update_player_bubbles(
            socket.assigns.typing_by_player,
            socket.assigns.player_id,
            :typing,
            text,
            nil
          )

        broadcast_typing(socket, text, socket.assigns.guess_result, :typing)
        assign(socket, :typing_by_player, typing_by_player)
      else
        socket
      end

    {:noreply, assign(socket, :input_text, text)}
  end

  def handle_event("typing", %{"guess" => text}, socket) when is_binary(text) do
    handle_event("typing", %{"guess" => %{"text" => text}}, socket)
  end

  def handle_event("typing", _params, socket), do: {:noreply, socket}

  def handle_event("submit_guess", %{"guess" => %{"text" => text}}, socket) do
    text = String.trim(text)

    cond do
      socket.assigns.game_state.phase != :in_progress ->
        {:noreply, clear_guess_input(socket)}

      text == "" ->
        {:noreply, socket}

      true ->
        bubble_id = submitted_bubble_id()

        result =
          Game.submit_guess(
            socket.assigns.room_id,
            socket.assigns.player_id,
            socket.assigns.player_name,
            text
          )

        guess_result = result && result.result

        broadcast_typing(socket, text, guess_result, :submitted, bubble_id)

        Process.send_after(
          self(),
          {:clear_submitted_typing, socket.assigns.player_id, bubble_id},
          @submitted_clear_delay_ms
        )

        {:noreply,
         socket
         |> assign(:guess_result, guess_result)
         |> assign(:input_text, "")
         |> assign(
           :typing_by_player,
           TypingBubble.update_player_bubbles(
             socket.assigns.typing_by_player,
             socket.assigns.player_id,
             :submitted,
             text,
             bubble_id
           )
         )
         |> assign(
           :guess_results,
           Map.put(socket.assigns.guess_results, socket.assigns.player_id, guess_result)
         )
         |> assign(:players, players(socket.assigns.room_id))}
    end
  end

  @impl true
  def handle_info({:game_state, game_state}, socket) do
    socket =
      if new_round?(socket.assigns.game_state, game_state) && socket.assigns.player_name do
        broadcast_typing(socket, "", nil, :typing)

        socket
        |> assign(:input_text, "")
        |> assign(:guess_result, nil)
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

  def handle_info(%Phoenix.Socket.Broadcast{topic: topic, event: "presence_diff"}, socket) do
    cond do
      topic == players_topic(socket.assigns.room_id) ->
        Lobby.touch_room(socket.assigns.room_id)
        {:noreply, assign(socket, :players, players(socket.assigns.room_id))}

      topic == color_topic(socket.assigns.room_id) && !socket.assigns.player_name ->
        {:noreply, assign_available_color(socket)}

      true ->
        {:noreply, socket}
    end
  end

  def handle_info({:clear_submitted_typing, player_id, bubble_id}, socket) do
    broadcast_typing(socket, "", nil, :remove_submitted, bubble_id)

    {:noreply,
     assign(
       socket,
       :typing_by_player,
       TypingBubble.update_player_bubbles(
         socket.assigns.typing_by_player,
         player_id,
         :remove_submitted,
         "",
         bubble_id
       )
     )}
  end

  def handle_info({:player_typing, player_id, text, guess_result}, socket) do
    handle_info({:player_typing, player_id, text, guess_result, :typing}, socket)
  end

  def handle_info({:player_typing, player_id, text, guess_result, mode}, socket) do
    handle_info({:player_typing, player_id, text, guess_result, mode, nil}, socket)
  end

  def handle_info({:player_typing, player_id, text, guess_result, mode, bubble_id}, socket) do
    {:noreply, queue_typing_update(socket, {player_id, text, guess_result, mode, bubble_id})}
  end

  def handle_info(:flush_typing_updates, socket) do
    updates =
      socket.private
      |> Map.get(:pending_typing_updates, [])
      |> Enum.reverse()

    {typing_by_player, guess_results} =
      TypingBubble.apply_updates(
        socket.assigns.typing_by_player,
        socket.assigns.guess_results,
        updates
      )

    socket =
      socket
      |> put_typing_private(:pending_typing_updates, [])
      |> put_typing_private(:typing_flush_scheduled?, false)

    {:noreply,
     socket
     |> assign(:typing_by_player, typing_by_player)
     |> assign(:guess_results, guess_results)}
  end

  defp submitted_bubble_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string()
  end

  defp clear_guess_input(socket) do
    socket =
      if socket.assigns.player_name do
        broadcast_typing(socket, "", socket.assigns.guess_result, :typing)

        assign(
          socket,
          :typing_by_player,
          TypingBubble.update_player_bubbles(
            socket.assigns.typing_by_player,
            socket.assigns.player_id,
            :typing,
            "",
            nil
          )
        )
      else
        socket
      end

    assign(socket, :input_text, "")
  end

  defp queue_typing_update(socket, update) do
    pending = [update | Map.get(socket.private, :pending_typing_updates, [])]
    flush_scheduled? = Map.get(socket.private, :typing_flush_scheduled?, false)

    socket = put_typing_private(socket, :pending_typing_updates, pending)

    if flush_scheduled? do
      socket
    else
      Process.send_after(self(), :flush_typing_updates, @typing_flush_ms)
      put_typing_private(socket, :typing_flush_scheduled?, true)
    end
  end

  defp put_typing_private(socket, key, value) do
    %{socket | private: Map.put(socket.private, key, value)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <%= if @player_name do %>
        <%= if @game_state.phase == :podium do %>
          <button
            phx-click="leave_room"
            class="fixed right-4 top-4 z-50 rounded-lg border border-gray-700 bg-gray-900/90 px-3 py-1.5 text-sm font-semibold text-gray-200 hover:border-indigo-500"
          >
            Leave Room
          </button>
          <.podium game_state={@game_state} players={@players} />
        <% else %>
          <.game_stage
            game_state={@game_state}
            players={@players}
            current_player_id={@player_id}
            typing_by_player={@typing_by_player}
            guess_results={@guess_results}
          >
            <button
              phx-click="leave_room"
              class="absolute right-4 top-4 z-50 rounded-lg border border-gray-700 bg-gray-900/90 px-3 py-1.5 text-sm font-semibold text-gray-200 hover:border-indigo-500"
            >
              Leave Room
            </button>

            <div
              :if={@game_state.phase == :standby}
              class="absolute left-1/2 top-4 z-10 -translate-x-1/2"
            >
              <div class="rounded-full border border-gray-700 bg-gray-800/80 px-6 py-2 text-sm text-gray-300">
                Waiting for admin to load a quiz
              </div>
            </div>

            <div
              :if={@game_state.phase == :loaded}
              class="absolute left-1/2 top-4 z-10 -translate-x-1/2"
            >
              <div class="rounded-full border border-indigo-700 bg-indigo-900/80 px-6 py-2 text-sm text-indigo-300">
                Quiz loaded. Waiting for admin to start
              </div>
            </div>

            <div
              :if={@game_state.phase in [:in_progress, :results]}
              class="keyboard-aware-answer-dock fixed inset-x-0 bottom-0 z-30 w-full bg-gradient-to-t from-gray-950 via-gray-950/95 to-transparent px-4 pb-[calc(env(safe-area-inset-bottom)+0.75rem)] pt-5 sm:absolute sm:bottom-8 sm:left-1/2 sm:max-w-md sm:-translate-x-1/2 sm:bg-none sm:p-0 sm:px-4"
            >
              <div
                :if={@game_state.phase == :results && @game_state.round_winner}
                class="mb-3 text-center"
              >
                <div class="inline-block rounded-xl bg-gray-800/90 px-4 py-2 text-sm">
                  <span :if={@game_state.round_winner.is_consolation} class="text-yellow-400">
                    Closest guess: <strong>{@game_state.round_winner.player_name}</strong>
                    (+{@game_state.round_winner.score})
                  </span>
                  <span :if={!@game_state.round_winner.is_consolation} class="text-green-400">
                    <strong>{@game_state.round_winner.player_name}</strong> got it
                    (+{@game_state.round_winner.score})
                  </span>
                </div>
              </div>

              <.form
                for={%{}}
                as={:guess}
                id="guess-form"
                phx-change="typing"
                phx-submit="submit_guess"
                phx-hook="GuessInputFocus"
              >
                <div class="relative">
                  <input
                    type="text"
                    name="guess[text]"
                    value={@input_text}
                    disabled={!can_input?(@game_state, @guess_result)}
                    placeholder={guess_placeholder(@game_state, @guess_result)}
                    autocomplete="off"
                    phx-throttle="40"
                    class={[
                      "w-full rounded-xl border-2 py-4 pl-5 pr-24 text-lg font-medium text-white outline-none transition-all disabled:cursor-not-allowed disabled:opacity-50",
                      input_result_class(@guess_result)
                    ]}
                  />
                  <button
                    type="submit"
                    disabled={!can_input?(@game_state, @guess_result)}
                    class="absolute right-2 top-1/2 -translate-y-1/2 rounded-lg border border-gray-700 bg-gray-900/80 px-3 py-1.5 text-sm font-bold text-gray-300 transition hover:border-indigo-500 hover:text-white disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    Enter
                  </button>
                </div>
              </.form>
            </div>
          </.game_stage>
        <% end %>
      <% else %>
        <main class="keyboard-aware-join-screen flex min-h-[var(--app-viewport-height,100svh)] items-center justify-center bg-gray-950 px-4 py-8 pb-[calc(env(safe-area-inset-bottom)+2rem)] text-white sm:min-h-screen">
          <%= if @room_password_required? && !@room_unlocked? do %>
            <div class="w-full max-w-sm text-center">
              <div class="mb-6 sm:mb-8">
                <div class="mb-4 text-sm font-black uppercase tracking-[0.22em] text-amber-300">
                  Locked room
                </div>
                <h1 class="mb-2 text-3xl font-bold sm:text-4xl">{@room.name}</h1>
                <p class="text-lg text-gray-400">Enter the room password</p>
              </div>

              <.form
                for={%{}}
                as={:room}
                phx-submit="unlock_room"
                class="flex flex-col items-center gap-4"
              >
                <div class="w-full max-w-xs">
                  <input
                    type="password"
                    name="room[password]"
                    placeholder="Room password"
                    maxlength="80"
                    autofocus
                    class="w-full rounded-xl border border-gray-600 bg-gray-800 px-6 py-3 text-center text-xl text-white outline-none transition focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/30"
                  />
                </div>
                <div :if={@room_password_error} class="text-sm font-semibold text-red-300">
                  {@room_password_error}
                </div>
                <button class="rounded-xl bg-indigo-600 px-8 py-3 text-lg font-bold text-white transition-colors hover:bg-indigo-500">
                  Continue
                </button>
              </.form>
            </div>
          <% else %>
            <div class="w-full max-w-sm text-center">
              <div class="mb-6 sm:mb-8">
                <div class="mb-4 text-6xl font-black text-indigo-300">?</div>
                <h1 class="mb-2 text-3xl font-bold sm:text-4xl">{@room.name}</h1>
                <p class="text-lg text-gray-400">Join as a player</p>
              </div>
              <.form
                for={%{}}
                as={:player}
                id="player-profile-form"
                phx-submit="join"
                phx-hook="PlayerProfileForm"
                class="flex flex-col items-center gap-4"
              >
                <input
                  type="text"
                  name="player[name]"
                  placeholder="Enter your name"
                  maxlength="20"
                  autofocus
                  class="w-full max-w-xs rounded-xl border border-gray-600 bg-gray-800 px-6 py-3 text-center text-xl text-white outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/30"
                />
                <div class="w-full max-w-xs">
                  <div class="mb-2 text-xs font-semibold uppercase tracking-[0.18em] text-gray-500">
                    Player color
                  </div>
                  <div class="grid grid-cols-8 gap-2.5 sm:gap-2">
                    <button
                      :for={color <- @player_colors}
                      type="button"
                      phx-click="choose_color"
                      phx-value-color={color}
                      disabled={color in @taken_colors}
                      class={[
                        "h-9 rounded-full border-2 transition disabled:cursor-not-allowed disabled:opacity-25 sm:h-8",
                        color == @candidate_color &&
                          "scale-110 border-white shadow-[0_0_18px_rgba(255,255,255,0.35)]",
                        color != @candidate_color && "border-gray-800 hover:border-white/70"
                      ]}
                      style={"background-color: #{color};"}
                      aria-label={"Choose #{color}"}
                    >
                    </button>
                  </div>
                </div>
                <button
                  type="submit"
                  disabled={is_nil(@candidate_color)}
                  class="rounded-xl bg-indigo-600 px-8 py-3 text-lg font-bold text-white transition-colors hover:bg-indigo-500 disabled:cursor-not-allowed disabled:opacity-40"
                >
                  Join Game
                </button>
              </.form>
            </div>
          <% end %>
        </main>
      <% end %>
    </Layouts.app>
    """
  end

  defp track_player(socket, name) do
    Presence.track(self(), players_topic(socket.assigns.room_id), socket.assigns.player_id, %{
      player_id: socket.assigns.player_id,
      name: name,
      color: socket.assigns.candidate_color,
      joined_at: System.system_time(:millisecond)
    })
  end

  defp reserve_player_slot(socket, room, true, room_id, player_id) do
    if connected?(socket) && room do
      Lobby.reserve_player(room_id, player_id)
    else
      :ok
    end
  end

  defp reserve_player_slot(_socket, _room, _joinable, _room_id, _player_id), do: :ok

  defp join_player(socket, _name, color)
       when not is_binary(color) do
    {:noreply, assign_available_color(socket)}
  end

  defp join_player(socket, name, color) do
    room_id = socket.assigns.room_id
    player_id = socket.assigns.player_id

    case Lobby.join_room(room_id, player_id, name, color) do
      :ok ->
        case track_player(socket, name) do
          {:ok, _ref} ->
            Presence.untrack(self(), color_topic(room_id), player_id)
            Lobby.touch_room(room_id)

            {:noreply,
             socket
             |> assign(:player_name, name)
             |> assign(:player_color, color)
             |> assign(:taken_colors, taken_colors(room_id, player_id))
             |> assign(:players, players(room_id))}

          {:error, _reason} ->
            Lobby.leave_room(room_id, player_id)

            {:noreply,
             socket
             |> put_flash(:error, "Could not join this room. Try again.")
             |> assign_available_color()}
        end

      {:error, :room_full} ->
        {:noreply,
         socket
         |> put_flash(:error, "This room is full.")
         |> assign_available_color()}

      {:error, :color_taken} ->
        {:noreply,
         socket
         |> put_flash(:error, "That color was just taken.")
         |> assign_available_color()}

      {:error, :game_in_progress} ->
        {:noreply,
         socket
         |> put_flash(:error, "This game is already in progress.")
         |> push_navigate(to: ~p"/")}

      {:error, :room_closed} ->
        {:noreply,
         socket
         |> put_flash(:error, "This room was closed.")
         |> push_navigate(to: ~p"/")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not join this room.")
         |> assign_available_color()}
    end
  end

  defp unlock_room(socket) do
    room_id = socket.assigns.room_id
    player_id = socket.assigns.player_id
    room = socket.assigns.room

    case reserve_player_slot(socket, room, socket.assigns.joinable, room_id, player_id) do
      :ok ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(LiveTrivia.PubSub, color_topic(room_id))
        end

        Lobby.touch_room(room_id)

        socket =
          socket
          |> assign(:room_unlocked?, true)
          |> assign(:room_password_error, nil)
          |> assign(:players, players(room_id))
          |> assign_available_color()

        update_color_selection(socket, socket.assigns.candidate_color)

        {:noreply, socket}

      {:error, :room_full} ->
        {:noreply,
         socket
         |> put_flash(:error, "This room is full.")
         |> push_navigate(to: ~p"/")}

      {:error, :game_in_progress} ->
        {:noreply,
         socket
         |> put_flash(:error, "This game is already in progress.")
         |> push_navigate(to: ~p"/")}

      {:error, :room_closed} ->
        {:noreply,
         socket
         |> put_flash(:error, "This room was closed.")
         |> push_navigate(to: ~p"/")}
    end
  end

  defp broadcast_typing(socket, typing_text, guess_result, mode, bubble_id \\ nil) do
    Phoenix.PubSub.broadcast_from(
      LiveTrivia.PubSub,
      self(),
      typing_topic(socket.assigns.room_id),
      {:player_typing, socket.assigns.player_id, typing_text, guess_result, mode, bubble_id}
    )
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
  defp color_topic(room_id), do: "color_select:#{room_id}"
  defp typing_topic(room_id), do: "typing:#{room_id}"

  defp track_color_selection(_room_id, _player_id, nil), do: :ok

  defp track_color_selection(room_id, player_id, color) do
    Presence.track(self(), color_topic(room_id), player_id, %{
      color: color,
      selected_at: System.system_time(:millisecond)
    })
  end

  defp update_color_selection(socket, color) do
    case Presence.update(
           self(),
           color_topic(socket.assigns.room_id),
           socket.assigns.player_id,
           fn meta ->
             Map.put(meta, :color, color)
           end
         ) do
      {:ok, _ref} ->
        :ok

      {:error, _reason} ->
        track_color_selection(socket.assigns.room_id, socket.assigns.player_id, color)
    end
  end

  defp initial_color(nil, _player_id, fallback), do: fallback

  defp initial_color(room_id, player_id, fallback) do
    taken = taken_colors(room_id, player_id)

    cond do
      PlayerColors.valid?(fallback) && fallback not in taken -> fallback
      true -> Enum.find(PlayerColors.all(), &(&1 not in taken))
    end
  end

  defp assign_available_color(socket) do
    taken = taken_colors(socket.assigns.room_id, socket.assigns.player_id)
    color = socket.assigns.candidate_color

    color =
      if PlayerColors.valid?(color) && color not in taken do
        color
      else
        Enum.find(PlayerColors.all(), &(&1 not in taken))
      end

    if color && color != socket.assigns.candidate_color do
      update_color_selection(socket, color)
    end

    socket
    |> assign(:candidate_color, color)
    |> assign(:taken_colors, taken_colors(socket.assigns.room_id, socket.assigns.player_id))
  end

  defp taken_colors(nil, _player_id), do: []

  defp taken_colors(room_id, player_id) do
    player_colors =
      room_id
      |> players_topic()
      |> Presence.list()
      |> Enum.flat_map(fn
        {^player_id, _presence} ->
          []

        {_id, %{metas: metas}} ->
          Enum.map(metas, & &1.color)
      end)

    selected_colors =
      room_id
      |> color_topic()
      |> Presence.list()
      |> Enum.flat_map(fn
        {^player_id, _presence} ->
          []

        {_id, %{metas: metas}} ->
          Enum.map(metas, & &1.color)
      end)

    reserved_colors = Lobby.taken_player_colors(room_id, player_id)

    (reserved_colors ++ player_colors ++ selected_colors)
    |> Enum.filter(&PlayerColors.valid?/1)
    |> Enum.uniq()
  end

  defp joinable?(%{phase: phase}), do: phase in [:standby, :loaded, :podium]
  defp joinable?(_game_state), do: false

  defp new_round?(old_state, new_state) do
    old_state.current_index != new_state.current_index ||
      (old_state.phase != new_state.phase && new_state.phase == :in_progress)
  end

  defp can_input?(%{phase: :in_progress}, result), do: result != :correct
  defp can_input?(_state, _result), do: false

  defp guess_placeholder(%{phase: :results}, _result), do: "Round over"
  defp guess_placeholder(_state, :correct), do: "Correct"
  defp guess_placeholder(_state, _result), do: "Take your guess!"

  defp input_result_class(:correct),
    do: "border-green-500 bg-green-900/50 shadow-[0_0_20px_rgba(34,197,94,0.4)]"

  defp input_result_class(:close),
    do: "border-yellow-500 bg-yellow-900/50 shadow-[0_0_20px_rgba(234,179,8,0.4)]"

  defp input_result_class(:near),
    do: "border-orange-500 bg-orange-900/50 shadow-[0_0_20px_rgba(249,115,22,0.4)]"

  defp input_result_class(:far),
    do: "border-red-500 bg-red-900/50 shadow-[0_0_20px_rgba(239,68,68,0.4)]"

  defp input_result_class(_result), do: "border-gray-600 bg-gray-800/80 focus:border-indigo-500"
end
