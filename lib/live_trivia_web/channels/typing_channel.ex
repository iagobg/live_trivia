defmodule LiveTriviaWeb.TypingChannel do
  use LiveTriviaWeb, :channel

  alias LiveTrivia.Lobby

  @max_text_length 80

  @impl true
  def join("typing:" <> room_id, _payload, socket) do
    case Lobby.get_room(room_id) do
      nil -> {:error, %{reason: "room_closed"}}
      _room -> {:ok, assign(socket, :room_id, room_id)}
    end
  end

  @impl true
  def handle_in("typing", payload, socket) do
    broadcast_from!(socket, "typing", normalize_typing_payload(payload))
    {:noreply, socket}
  end

  defp normalize_typing_payload(payload) do
    %{
      p: payload |> compact_get("p", "player_id") |> to_string() |> String.slice(0, 80),
      t: payload |> compact_get("t", "text") |> to_string() |> String.slice(0, @max_text_length)
    }
  end

  defp compact_get(payload, compact_key, verbose_key) do
    Map.get(payload, compact_key) || Map.get(payload, verbose_key)
  end
end
