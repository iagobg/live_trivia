defmodule LiveTriviaWeb.LobbyLive do
  use LiveTriviaWeb, :live_view

  alias LiveTrivia.Lobby

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Lobby.subscribe()
      # Trigger the deferred load for the initial connection
      send(self(), :load_rooms)
    end

    {:ok,
     socket
     |> assign(:page_title, "Live Trivia Lobby")
     |> assign(:player_id, Map.fetch!(session, "player_id"))
     |> assign(:rooms, [])
     |> assign(:rooms_loaded?, false)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("create_room", %{"room" => room_params}, socket) do
    name = Map.get(room_params, "name", "")

    password =
      if Map.get(room_params, "password_enabled") == "true",
        do: Map.get(room_params, "password", ""),
        else: nil

    case Lobby.create_room(name, socket.assigns.player_id, password) do
      {:ok, room} ->
        {:noreply, push_navigate(socket, to: ~p"/rooms/#{room.id}/admin")}

      {:error, :room_limit} ->
        {:noreply, assign(socket, :error, "Room limit reached. Try again soon.")}
    end
  end

  @impl true
  def handle_info(:load_rooms, socket) do
    {:noreply,
     socket
     |> assign(:rooms, Lobby.list_rooms())
     |> assign(:rooms_loaded?, true)}
  end

  @impl true
  def handle_info({:rooms_updated, rooms}, socket) do
    {:noreply,
     socket
     |> assign(:rooms, rooms)
     |> assign(:rooms_loaded?, true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <main class="relative min-h-[100svh] overflow-hidden bg-gray-950 px-4 pb-[calc(env(safe-area-inset-bottom)+2rem)] pt-8 text-white sm:min-h-screen sm:py-10">
        <div class="pointer-events-none absolute inset-0 opacity-30">
          <div
            :for={i <- 1..60}
            class="star"
            style={"--x: #{rem(i * 37, 100)}%; --y: #{rem(i * 53, 100)}%;"}
          />
        </div>

        <div class="relative z-10 mx-auto flex w-full max-w-5xl flex-col gap-8">
          <header class="flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <div class="text-sm font-semibold uppercase tracking-[0.22em] text-indigo-300">
                Live Trivia
              </div>
              <h1 class="mt-2 text-3xl font-black sm:text-4xl">Open Rooms</h1>
              <p class="mt-2 max-w-xl text-sm text-gray-400">
                Create a room, load a quiz, and invite players into the live game.
              </p>
            </div>

            <.form
              for={%{}}
              as={:room}
              phx-submit="create_room"
              id="create-room-form"
              phx-hook="RoomPasswordToggle"
              class="grid w-full gap-2 rounded-xl border border-gray-800 bg-gray-900/50 p-2 sm:w-auto sm:grid-cols-[13rem_11rem_auto] sm:items-center sm:border-0 sm:bg-transparent sm:p-0"
            >
              <div class="sm:col-start-1">
                <input
                  type="text"
                  name="room[name]"
                  maxlength="40"
                  placeholder="Room name"
                  class="w-full rounded-xl border border-gray-700 bg-gray-900 px-4 py-3 text-sm text-white outline-none transition focus:border-indigo-500"
                />
              </div>

              <div class="sm:col-start-2">
                <input
                  type="password"
                  name="room[password]"
                  data-role="room-password"
                  disabled
                  maxlength="80"
                  placeholder="Password"
                  class="w-full rounded-xl border border-gray-700 bg-gray-900 px-4 py-3 text-sm text-white outline-none transition focus:border-indigo-500 disabled:bg-gray-900/40 disabled:text-gray-600 disabled:placeholder:text-gray-700"
                />
              </div>

              <div class="flex items-center gap-3 sm:col-start-3">
                <label class="flex items-center gap-2 rounded-xl border border-gray-800 bg-gray-900/80 px-3 py-3 text-xs font-semibold text-gray-300">
                  <input
                    type="checkbox"
                    name="room[password_enabled]"
                    data-role="room-password-enabled"
                    value="true"
                    class="h-4 w-4 rounded border-gray-600 bg-gray-950 text-indigo-600"
                  /> Password
                </label>
                <button class="flex-1 rounded-xl bg-indigo-600 px-4 py-3 text-sm font-bold text-white transition hover:bg-indigo-500">
                  Create
                </button>
              </div>
            </.form>
          </header>

          <div
            :if={@error}
            class="rounded-xl border border-red-700 bg-red-950/60 px-4 py-3 text-sm text-red-200"
          >
            {@error}
          </div>

          <section class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <.room_card :for={room <- @rooms} room={room} />

            <div
              :if={@rooms == []}
              class="col-span-full rounded-xl border border-dashed border-gray-800 bg-gray-900/40 px-6 py-12 text-center text-gray-400"
            >
              <%= if @rooms_loaded? do %>
                No rooms open yet.
              <% else %>
                Loading rooms...
              <% end %>
            </div>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end

  attr :room, :map, required: true

  defp room_card(assigns) do
    ~H"""
    <%= if @room.joinable do %>
      <.link
        navigate={~p"/rooms/#{@room.id}"}
        class="group block min-h-32 rounded-xl border border-gray-800 bg-gray-900/80 p-4 transition hover:border-indigo-500 hover:bg-gray-900 active:scale-[0.99]"
      >
        <.room_card_content room={@room} />
      </.link>
    <% else %>
      <div class="min-h-32 rounded-xl border border-gray-800 bg-gray-900/80 p-4 opacity-60">
        <.room_card_content room={@room} />
      </div>
    <% end %>
    """
  end

  attr :room, :map, required: true

  defp room_card_content(assigns) do
    ~H"""
    <div class="flex min-h-24 flex-col justify-between gap-4">
      <div class="min-w-0 border-b border-gray-800 pb-3">
        <div class="line-clamp-2 text-lg font-bold leading-snug text-white">{@room.name}</div>
      </div>

      <div class="grid grid-cols-2 gap-1.5">
        <div class="rounded-lg bg-indigo-500/15 px-2 py-1.5 text-xs font-semibold text-indigo-200">
          {@room.player_count} player{if @room.player_count == 1, do: "", else: "s"}
        </div>
        <div class="rounded-lg bg-emerald-500/15 px-2 py-1.5 text-xs font-semibold text-emerald-200">
          {@room.admin_count} admin{if @room.admin_count == 1, do: "", else: "s"}
        </div>
        <div class="rounded-lg bg-amber-500/15 px-2 py-1.5 text-xs font-semibold uppercase text-amber-200">
          {if @room.password_protected?, do: "Locked", else: "Open"}
        </div>
        <div class="truncate rounded-lg bg-gray-800 px-2 py-1.5 text-xs font-semibold uppercase text-gray-400">
          {@room.round_label || phase_label(@room.phase)}
        </div>
      </div>
    </div>
    """
  end

  defp phase_label(phase), do: phase |> Atom.to_string() |> String.replace("_", " ")
end
