defmodule LiveTriviaWeb.TypingChannel do
  use LiveTriviaWeb, :channel

  alias LiveTrivia.Lobby

  @max_text_length 80

  @impl true
  def join("t:" <> topic_id, _payload, socket), do: join_topic(topic_id, socket)

  def join("typing:" <> room_id, _payload, socket) do
    join_room(room_id, socket)
  end

  @impl true
  def handle_in(event, payload, socket) when event in ["t", "typing"] do
    start_time = System.monotonic_time()
    normalized_payload = normalize_typing_payload(payload)

    broadcast_from!(socket, "t", normalized_payload)
    emit_benchmark_telemetry(socket, normalized_payload, start_time)

    {:noreply, socket}
  end

  defp join_room(room_id, socket) do
    case Lobby.get_room(room_id) do
      nil -> {:error, %{reason: "room_closed"}}
      _room -> {:ok, assign(socket, :room_id, room_id)}
    end
  end

  defp join_topic(topic_id, socket) do
    case Lobby.room_id_for_topic(topic_id) do
      nil -> join_room(topic_id, socket)
      room_id -> join_room(room_id, socket)
    end
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
      i: payload |> compact_get("i", "player_slot") |> normalize_player_slot(),
      p: payload |> compact_get("p", "player_id") |> normalize_legacy_player_id(),
      t: payload |> compact_get("t", "text") |> to_string() |> String.slice(0, @max_text_length)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> maybe_put_timestamp(payload)
  end

  defp normalize_player_slot(slot) when is_integer(slot) and slot >= 0 and slot <= 15, do: slot

  defp normalize_player_slot(slot) when is_binary(slot) do
    case Integer.parse(slot) do
      {slot, ""} -> normalize_player_slot(slot)
      _other -> nil
    end
  end

  defp normalize_player_slot(_slot), do: nil

  defp normalize_legacy_player_id(nil), do: nil
  defp normalize_legacy_player_id(player_id), do: player_id |> to_string() |> String.slice(0, 80)

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
