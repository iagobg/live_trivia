defmodule LiveTriviaWeb.PlayerLive do
  use LiveTriviaWeb, :live_view

  alias LiveTrivia.Game
  alias LiveTriviaWeb.Presence
  import LiveTriviaWeb.TriviaComponents

  @players_topic "players"

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Game.subscribe()
      Phoenix.PubSub.subscribe(LiveTrivia.PubSub, @players_topic)
    end

    player_id = Map.fetch!(session, "player_id")
    player_color = Map.fetch!(session, "player_color")

    socket =
      socket
      |> assign(:page_title, "Live Trivia")
      |> assign(:game_state, Game.get_state())
      |> assign(:players, players())
      |> assign(:player_id, player_id)
      |> assign(:player_color, player_color)
      |> assign(:player_name, nil)
      |> assign(:input_text, "")
      |> assign(:guess_result, nil)
      |> assign(:previous_round, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("join", %{"player" => %{"name" => name}}, socket) do
    name = name |> String.trim() |> String.slice(0, 20)

    if name == "" do
      {:noreply, socket}
    else
      track_player(socket, name, "", nil)

      {:noreply,
       socket
       |> assign(:player_name, name)
       |> assign(:players, players())}
    end
  end

  def handle_event("typing", %{"guess" => %{"text" => text}}, socket) do
    text = String.slice(text, 0, 80)

    if socket.assigns.player_name do
      update_player(socket, text, socket.assigns.guess_result)
    end

    {:noreply, assign(socket, :input_text, text)}
  end

  def handle_event("submit_guess", %{"guess" => %{"text" => text}}, socket) do
    text = String.trim(text)

    cond do
      socket.assigns.game_state.phase != :in_progress ->
        {:noreply, socket}

      text == "" ->
        {:noreply, socket}

      true ->
        result = Game.submit_guess(socket.assigns.player_id, socket.assigns.player_name, text)
        guess_result = result && result.result
        input_text = if guess_result == :correct, do: "", else: socket.assigns.input_text

        update_player(socket, "", guess_result)

        {:noreply,
         socket
         |> assign(:guess_result, guess_result)
         |> assign(:input_text, input_text)
         |> assign(:players, players())}
    end
  end

  @impl true
  def handle_info({:game_state, game_state}, socket) do
    socket =
      if new_round?(socket.assigns.game_state, game_state) && socket.assigns.player_name do
        update_player(socket, "", nil)

        socket
        |> assign(:input_text, "")
        |> assign(:guess_result, nil)
      else
        socket
      end

    {:noreply, assign(socket, :game_state, game_state)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, :players, players())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <%= if @player_name do %>
        <%= if @game_state.phase == :podium do %>
          <.podium game_state={@game_state} players={@players} />
        <% else %>
          <.game_stage game_state={@game_state} players={@players} current_player_id={@player_id}>
            <div
              :if={@game_state.so_close_player_id}
              class="absolute left-1/2 top-20 z-50 -translate-x-1/2 animate-bounce"
            >
              <div class="rounded-xl bg-yellow-500 px-6 py-3 text-xl font-bold text-black shadow-2xl">
                So close: {@game_state.so_close_player_name}
              </div>
            </div>

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
              class="absolute bottom-8 left-1/2 z-20 w-full max-w-md -translate-x-1/2 px-4"
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

              <.form for={%{}} as={:guess} phx-change="typing" phx-submit="submit_guess">
                <div class="relative">
                  <input
                    type="text"
                    name="guess[text]"
                    value={@input_text}
                    disabled={!can_input?(@game_state, @guess_result)}
                    placeholder={guess_placeholder(@game_state, @guess_result)}
                    autocomplete="off"
                    class={[
                      "w-full rounded-xl border-2 px-5 py-4 text-lg font-medium text-white outline-none transition-all disabled:cursor-not-allowed disabled:opacity-50",
                      input_result_class(@guess_result)
                    ]}
                  />
                  <div class="absolute right-4 top-1/2 -translate-y-1/2 text-sm text-gray-500">
                    Enter
                  </div>
                </div>
              </.form>
            </div>
          </.game_stage>
        <% end %>
      <% else %>
        <main class="flex min-h-screen items-center justify-center bg-gray-950 px-4 text-white">
          <div class="text-center">
            <div class="mb-8">
              <div class="mb-4 text-6xl font-black text-indigo-300">?</div>
              <h1 class="mb-2 text-4xl font-bold">Live Trivia</h1>
              <p class="text-lg text-gray-400">Real-time trivia</p>
            </div>
            <.form for={%{}} as={:player} phx-submit="join" class="flex flex-col items-center gap-4">
              <input
                type="text"
                name="player[name]"
                placeholder="Enter your name"
                maxlength="20"
                autofocus
                class="w-72 rounded-xl border border-gray-600 bg-gray-800 px-6 py-3 text-center text-xl text-white outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/30"
              />
              <button
                type="submit"
                class="rounded-xl bg-indigo-600 px-8 py-3 text-lg font-bold text-white transition-colors hover:bg-indigo-500"
              >
                Join Game
              </button>
            </.form>
          </div>
        </main>
      <% end %>
    </Layouts.app>
    """
  end

  defp track_player(socket, name, typing_text, guess_result) do
    Presence.track(self(), @players_topic, socket.assigns.player_id, %{
      player_id: socket.assigns.player_id,
      name: name,
      color: socket.assigns.player_color,
      typing_text: typing_text,
      guess_result: guess_result,
      joined_at: System.system_time(:millisecond)
    })
  end

  defp update_player(socket, typing_text, guess_result) do
    Presence.update(self(), @players_topic, socket.assigns.player_id, fn meta ->
      meta
      |> Map.put(:typing_text, typing_text)
      |> Map.put(:guess_result, guess_result)
    end)
  end

  defp players do
    @players_topic
    |> Presence.list()
    |> Enum.map(fn {player_id, %{metas: [meta | _]}} -> Map.put(meta, :player_id, player_id) end)
    |> Enum.sort_by(& &1.joined_at)
  end

  defp new_round?(old_state, new_state) do
    old_state.current_index != new_state.current_index ||
      (old_state.phase != new_state.phase && new_state.phase == :in_progress)
  end

  defp can_input?(%{phase: :in_progress}, result), do: result != :correct
  defp can_input?(_state, _result), do: false

  defp guess_placeholder(%{phase: :results}, _result), do: "Round over"
  defp guess_placeholder(_state, :correct), do: "Correct"
  defp guess_placeholder(_state, _result), do: "Type your answer and press Enter"

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
