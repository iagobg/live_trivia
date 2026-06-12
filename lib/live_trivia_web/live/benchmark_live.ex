defmodule LiveTriviaWeb.BenchmarkLive do
  use LiveTriviaWeb, :live_view

  alias LiveTrivia.Lobby

  @impl true
  def mount(_params, session, socket) do
    socket = assign(socket, :page_title, "Synthetic Benchmark")

    if connected?(socket) do
      player_id = Map.fetch!(session, "player_id")
      room_name = "Benchmark #{DateTime.utc_now() |> Calendar.strftime("%H:%M:%S")}"

      case Lobby.create_room(room_name, player_id) do
        {:ok, room} ->
          {:ok, push_navigate(socket, to: ~p"/rooms/#{room.id}/admin?benchmark=synthetic")}

        {:error, :room_limit} ->
          {:ok,
           put_flash(socket, :error, "Room limit reached. Close an existing room and try again.")}
      end
    else
      {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <main class="flex min-h-[100svh] items-center justify-center bg-gray-950 p-6 text-white">
        <div class="text-center">
          <div class="text-sm font-semibold uppercase tracking-[0.22em] text-indigo-300">
            Benchmark
          </div>
          <h1 class="mt-2 text-2xl font-black">Preparing synthetic room...</h1>
        </div>
      </main>
    </Layouts.app>
    """
  end
end
