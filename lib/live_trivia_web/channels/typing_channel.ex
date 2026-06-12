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
    start_time = System.monotonic_time()
    normalized_payload = normalize_typing_payload(payload)

    broadcast_from!(socket, "typing", normalized_payload)
    emit_benchmark_telemetry(socket, normalized_payload, start_time)

    {:noreply, socket}
  end

  defp emit_benchmark_telemetry(socket, payload, start_time) do
    if LiveTrivia.Benchmark.Telemetry.enabled?() do
      :telemetry.execute(
        [:live_trivia, :typing_channel, :typing],
        %{
          count: 1,
          duration: System.monotonic_time() - start_time,
          payload_bytes: IO.iodata_length(Jason.encode_to_iodata!(payload))
        },
        %{room_id: socket.assigns.room_id}
      )
    end
  end

  defp normalize_typing_payload(payload) do
    %{
      p: payload |> compact_get("p", "player_id") |> to_string() |> String.slice(0, 80),
      t: payload |> compact_get("t", "text") |> to_string() |> String.slice(0, @max_text_length)
    }
    |> maybe_put_timestamp(payload)
  end

  defp maybe_put_timestamp(normalized_payload, payload) do
    case Map.get(payload, "ts") do
      nil -> normalized_payload
      timestamp when is_number(timestamp) -> Map.put(normalized_payload, :ts, timestamp)
      _timestamp -> normalized_payload
    end
  end

  defp compact_get(payload, compact_key, verbose_key) do
    Map.get(payload, compact_key) || Map.get(payload, verbose_key)
  end
end
