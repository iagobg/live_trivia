defmodule LiveTriviaWeb.TypingChannel do
  use LiveTriviaWeb, :channel

  alias LiveTrivia.Lobby

  @max_text_length 80
  @timestamp_flag 16

  @impl true
  def join("t:" <> topic_id, _payload, socket), do: join_topic(topic_id, socket)

  def join("typing:" <> room_id, _payload, socket) do
    join_room(room_id, socket)
  end

  @impl true
  def handle_in(event, payload, socket) when event in ["t", "typing"] do
    start_time = System.monotonic_time()
    normalized_payload = normalize_typing_payload(payload)

    broadcast_from!(socket, "t", binary_payload(normalized_payload))
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
          payload_bytes: payload_size(payload)
        },
        %{room_id: socket.assigns.room_id}
      )
    end
  end

  defp payload_size({:binary, payload}), do: byte_size(payload)
  defp payload_size(payload), do: IO.iodata_length(Jason.encode_to_iodata!(payload))

  defp normalize_typing_payload({:binary, payload}), do: normalize_binary_typing_payload(payload)

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

  defp normalize_binary_typing_payload(<<flags, timestamp::float-64, text::binary>>)
       when Bitwise.band(flags, @timestamp_flag) != 0 do
    %{
      i: Bitwise.band(flags, 15),
      t: String.slice(text, 0, @max_text_length),
      ts: timestamp
    }
  end

  defp normalize_binary_typing_payload(<<flags, text::binary>>) do
    %{
      i: Bitwise.band(flags, 15),
      t: String.slice(text, 0, @max_text_length)
    }
  end

  defp normalize_binary_typing_payload(_payload), do: %{i: 0, t: ""}

  defp binary_payload(%{i: player_slot, t: text} = payload) when is_integer(player_slot) do
    flags =
      if Map.has_key?(payload, :ts) do
        Bitwise.bor(player_slot, @timestamp_flag)
      else
        player_slot
      end

    data =
      case payload do
        %{ts: timestamp} -> <<flags, timestamp::float-64, text::binary>>
        _payload -> <<flags, text::binary>>
      end

    {:binary, data}
  end

  defp binary_payload(payload), do: payload

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
