defmodule LiveTriviaWeb.LobbyLive do
  use LiveTriviaWeb, :live_view

  alias LiveTrivia.Lobby

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket), do: Lobby.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Live Trivia Lobby")
     |> assign(:player_id, Map.fetch!(session, "player_id"))
     |> assign(:rooms, Lobby.list_rooms())
     |> assign(:room_name, "")
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("create_room", %{"room" => %{"name" => name}}, socket) do
    case Lobby.create_room(name, socket.assigns.player_id) do
      {:ok, room} ->
        {:noreply, push_navigate(socket, to: ~p"/rooms/#{room.id}/admin")}

      {:error, :room_limit} ->
        {:noreply, assign(socket, :error, "Room limit reached. Try again soon.")}
    end
  end

  @impl true
  def handle_info({:rooms_updated, rooms}, socket) do
    {:noreply, assign(socket, :rooms, rooms)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <main class="relative min-h-screen overflow-hidden bg-gray-950 px-4 py-10 text-white">
        <div class="pointer-events-none absolute inset-0 opacity-30">
          <div
            :for={i <- 1..60}
            class="star"
            style={"--x: #{rem(i * 37, 100)}%; --y: #{rem(i * 53, 100)}%;"}
          />
        </div>

        <div class="relative z-10 mx-auto flex w-full max-w-5xl flex-col gap-8">
          <header class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <div class="text-sm font-semibold uppercase tracking-[0.22em] text-indigo-300">
                Live Trivia
              </div>
              <h1 class="mt-2 text-4xl font-black">Open Rooms</h1>
              <p class="mt-2 max-w-xl text-sm text-gray-400">
                Create a room, load a quiz, and invite players into the live game.
              </p>
            </div>

            <.form for={%{}} as={:room} phx-submit="create_room" class="flex gap-2">
              <input
                type="text"
                name="room[name]"
                maxlength="40"
                placeholder="Room name"
                class="w-52 rounded-xl border border-gray-700 bg-gray-900 px-4 py-3 text-sm text-white outline-none focus:border-indigo-500"
              />
              <button class="rounded-xl bg-indigo-600 px-4 py-3 text-sm font-bold text-white transition hover:bg-indigo-500">
                Create
              </button>
            </.form>
          </header>

          <div
            :if={@error}
            class="rounded-xl border border-red-700 bg-red-950/60 px-4 py-3 text-sm text-red-200"
          >
            {@error}
          </div>

          <section class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <div
              :for={room <- @rooms}
              class={[
                "rounded-xl border bg-gray-900/80 p-4 transition",
                if(room.joinable,
                  do: "group border-gray-800 hover:border-indigo-500 hover:bg-gray-900",
                  else: "border-gray-800 opacity-60"
                )
              ]}
            >
              <div class="flex items-start justify-between gap-3">
                <div class="min-w-0">
                  <div class="truncate text-lg font-bold text-white">{room.name}</div>
                  <div class="mt-1 font-mono text-xs uppercase text-gray-500">{room.id}</div>
                </div>
                <div class="flex flex-col items-end gap-1">
                  <div class="rounded-full bg-indigo-500/15 px-2 py-1 text-xs font-semibold text-indigo-200">
                    {room.player_count} player{if room.player_count == 1, do: "", else: "s"}
                  </div>
                  <div class="rounded-full bg-emerald-500/15 px-2 py-1 text-[0.65rem] font-semibold text-emerald-200">
                    {room.admin_count} admin{if room.admin_count == 1, do: "", else: "s"}
                  </div>
                  <div class="rounded-full bg-gray-800 px-2 py-1 text-[0.65rem] font-semibold uppercase text-gray-400">
                    {room.phase |> Atom.to_string() |> String.replace("_", " ")}
                  </div>
                </div>
              </div>
              <.link
                :if={room.joinable}
                navigate={~p"/rooms/#{room.id}"}
                class="mt-5 block text-sm font-semibold text-indigo-300 transition group-hover:text-indigo-200"
              >
                Join room
              </.link>
              <div :if={!room.joinable} class="mt-5 text-sm font-semibold text-gray-500">
                Game in progress
              </div>
            </div>

            <div
              :if={@rooms == []}
              class="col-span-full rounded-xl border border-dashed border-gray-800 bg-gray-900/40 px-6 py-12 text-center text-gray-400"
            >
              No rooms open yet.
            </div>
          </section>
        </div>
      </main>
    </Layouts.app>
    """
  end
end
