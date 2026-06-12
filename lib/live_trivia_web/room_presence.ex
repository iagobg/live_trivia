defmodule LiveTriviaWeb.RoomPresence do
  alias LiveTriviaWeb.Presence

  def players(room_id) do
    room_id
    |> players_topic()
    |> Presence.list()
    |> Enum.map(fn {player_id, %{metas: [meta | _]}} -> Map.put(meta, :player_id, player_id) end)
    |> Enum.sort_by(& &1.joined_at)
  end

  def track_player(room_id, player_id, name, color) do
    Presence.track(self(), players_topic(room_id), player_id, %{
      player_id: player_id,
      name: name,
      color: color,
      joined_at: System.system_time(:millisecond)
    })
  end

  def track_admin(room_id, admin_id) do
    Presence.track(self(), admins_topic(room_id), admin_id, %{
      admin_id: admin_id,
      joined_at: System.system_time(:millisecond)
    })
  end

  def track_color_selection(_room_id, _player_id, nil), do: :ok

  def track_color_selection(room_id, player_id, color) do
    Presence.track(self(), color_topic(room_id), player_id, %{
      color: color,
      selected_at: System.system_time(:millisecond)
    })
  end

  def update_color_selection(room_id, player_id, color) do
    case Presence.update(self(), color_topic(room_id), player_id, &Map.put(&1, :color, color)) do
      {:ok, _ref} -> :ok
      {:error, _reason} -> track_color_selection(room_id, player_id, color)
    end
  end

  def selected_colors(room_id, player_id) do
    room_id
    |> color_topic()
    |> colors_from_presence(player_id)
  end

  def player_colors(room_id, player_id) do
    room_id
    |> players_topic()
    |> colors_from_presence(player_id)
  end

  def subscribe(room_id) do
    Phoenix.PubSub.subscribe(LiveTrivia.PubSub, players_topic(room_id))
    Phoenix.PubSub.subscribe(LiveTrivia.PubSub, room_topic(room_id))
  end

  def players_topic(room_id), do: "players:#{room_id}"
  def admins_topic(room_id), do: "admins:#{room_id}"
  def room_topic(room_id), do: "room:#{room_id}"
  def color_topic(room_id), do: "color_select:#{room_id}"
  def typing_topic(room_id), do: "typing:#{room_id}"

  defp colors_from_presence(topic, player_id) do
    topic
    |> Presence.list()
    |> Enum.flat_map(fn
      {^player_id, _presence} -> []
      {_id, %{metas: metas}} -> Enum.map(metas, & &1.color)
    end)
  end
end
