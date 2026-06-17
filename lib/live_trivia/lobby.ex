defmodule LiveTrivia.Lobby do
  use GenServer

  alias LiveTrivia.PlayerColors

  @topic "lobby"
  @max_rooms 16
  @max_players 16
  @sweep_interval_ms 60_000
  @inactive_after_ms 5 * 60_000
  @podium_close_after_ms 30_000

  defmodule Room do
    defstruct [
      :id,
      :name,
      :admin_id,
      :game_pid,
      :created_at,
      :updated_at,
      :topic_id,
      :password_hash,
      :password_salt,
      player_colors: %{}
    ]
  end

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def subscribe, do: Phoenix.PubSub.subscribe(LiveTrivia.PubSub, @topic)

  def list_rooms, do: GenServer.call(__MODULE__, :list_rooms)

  def get_room(room_id), do: GenServer.call(__MODULE__, {:get_room, room_id})

  def room_id_for_topic(topic_id), do: GenServer.call(__MODULE__, {:room_id_for_topic, topic_id})

  def room_topic_id(room_id), do: GenServer.call(__MODULE__, {:room_topic_id, room_id})

  def create_room(name, admin_id, password \\ nil) do
    GenServer.call(__MODULE__, {:create_room, name, admin_id, password})
  end

  def verify_room_password(room_id, password),
    do: GenServer.call(__MODULE__, {:verify_room_password, room_id, password})

  def close_room(room_id), do: GenServer.call(__MODULE__, {:close_room, room_id})

  def reserve_player(room_id, player_id),
    do: GenServer.call(__MODULE__, {:reserve_player, room_id, player_id})

  def join_room(room_id, player_id, name, color),
    do: GenServer.call(__MODULE__, {:join_room, room_id, player_id, name, color})

  def leave_room(room_id, player_id),
    do: GenServer.call(__MODULE__, {:leave_room, room_id, player_id})

  def taken_player_colors(room_id, player_id),
    do: GenServer.call(__MODULE__, {:taken_player_colors, room_id, player_id})

  def touch_room(room_id), do: GenServer.cast(__MODULE__, {:touch_room, room_id})

  def room_state_changed(room_id, phase),
    do: GenServer.cast(__MODULE__, {:room_state_changed, room_id, phase})

  def admin_left(room_id), do: GenServer.cast(__MODULE__, {:admin_left, room_id})

  def player_count(room_id) do
    "players:#{room_id}"
    |> LiveTriviaWeb.Presence.list()
    |> map_size()
  end

  def admin_count(room_id) do
    "admins:#{room_id}"
    |> LiveTriviaWeb.Presence.list()
    |> map_size()
  end

  def active_count(room_id), do: player_count(room_id) + admin_count(room_id)

  def joinable?(room_id) do
    room_id
    |> safe_game_state()
    |> joinable_state?()
  end

  @impl true
  def init(state) do
    Process.send_after(self(), :sweep_inactive_rooms, @sweep_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call(:list_rooms, _from, rooms) do
    {:reply, public_rooms(rooms), rooms}
  end

  def handle_call({:get_room, room_id}, _from, rooms) do
    {:reply, Map.get(rooms, room_id), rooms}
  end

  def handle_call({:room_id_for_topic, topic_id}, _from, rooms) do
    room_id =
      rooms
      |> Enum.find_value(fn {room_id, room} ->
        if room.topic_id == topic_id, do: room_id
      end)

    {:reply, room_id, rooms}
  end

  def handle_call({:room_topic_id, room_id}, _from, rooms) do
    topic_id =
      rooms
      |> Map.get(room_id)
      |> case do
        nil -> nil
        room -> room.topic_id
      end

    {:reply, topic_id, rooms}
  end

  def handle_call({:create_room, name, admin_id, password}, _from, rooms) do
    if map_size(rooms) >= @max_rooms do
      {:reply, {:error, :room_limit}, rooms}
    else
      room_id = random_id()
      {password_hash, password_salt} = password_credentials(password)

      {:ok, game_pid} =
        DynamicSupervisor.start_child(
          LiveTrivia.RoomSupervisor,
          {LiveTrivia.Game, room_id: room_id}
        )

      now = now_ms()

      room = %Room{
        id: room_id,
        name: normalize_name(name, room_id),
        admin_id: admin_id,
        game_pid: game_pid,
        created_at: now,
        updated_at: now,
        topic_id: next_topic_id(rooms),
        password_hash: password_hash,
        password_salt: password_salt
      }

      rooms = Map.put(rooms, room_id, room)
      broadcast_rooms(rooms)
      {:reply, {:ok, room}, rooms}
    end
  end

  def handle_call({:verify_room_password, room_id, password}, _from, rooms) do
    result =
      case Map.get(rooms, room_id) do
        nil -> {:error, :room_closed}
        %{password_hash: nil} -> :ok
        room -> verify_password(room, password)
      end

    {:reply, result, rooms}
  end

  def handle_call({:close_room, room_id}, _from, rooms) do
    rooms = close_room(rooms, room_id)
    broadcast_rooms(rooms)
    {:reply, :ok, rooms}
  end

  def handle_call({:reserve_player, room_id, player_id}, _from, rooms) do
    case reserve_player_slot(rooms, room_id, player_id) do
      {:ok, rooms} ->
        broadcast_rooms(rooms)
        {:reply, :ok, rooms}

      {:error, reason} ->
        {:reply, {:error, reason}, rooms}
    end
  end

  def handle_call({:join_room, room_id, player_id, name, color}, _from, rooms) do
    case admit_player(rooms, room_id, player_id, name, color) do
      {:ok, rooms} ->
        broadcast_rooms(rooms)
        {:reply, :ok, rooms}

      {:error, reason} ->
        {:reply, {:error, reason}, rooms}
    end
  end

  def handle_call({:taken_player_colors, room_id, player_id}, _from, rooms) do
    colors =
      rooms
      |> Map.get(room_id)
      |> case do
        nil ->
          []

        room ->
          room.player_colors
          |> Map.delete(player_id)
          |> Map.values()
          |> Enum.filter(&PlayerColors.valid?/1)
          |> Enum.uniq()
      end

    {:reply, colors, rooms}
  end

  def handle_call({:leave_room, room_id, player_id}, _from, rooms) do
    rooms = release_player_slot(rooms, room_id, player_id)
    broadcast_rooms(rooms)
    {:reply, :ok, rooms}
  end

  @impl true
  def handle_cast({:touch_room, room_id}, rooms) do
    rooms =
      Map.update(rooms, room_id, nil, fn
        nil -> nil
        room -> %{room | updated_at: now_ms()}
      end)
      |> Enum.reject(fn {_room_id, room} -> is_nil(room) end)
      |> Map.new()

    broadcast_rooms(rooms)
    {:noreply, rooms}
  end

  def handle_cast({:room_state_changed, room_id, phase}, rooms) do
    rooms =
      rooms
      |> touch_room_in_memory(room_id)
      |> maybe_close_for_occupancy(room_id, phase)

    broadcast_rooms(rooms)
    {:noreply, rooms}
  end

  def handle_cast({:admin_left, room_id}, rooms) do
    phase = room_phase(safe_game_state(room_id))
    rooms = maybe_close_for_occupancy(rooms, room_id, phase)
    broadcast_rooms(rooms)
    {:noreply, rooms}
  end

  @impl true
  def handle_info(:sweep_inactive_rooms, rooms) do
    cutoff = now_ms() - @inactive_after_ms

    rooms =
      rooms
      |> Enum.reduce(rooms, fn {room_id, room}, acc ->
        if room.updated_at < cutoff do
          close_room(acc, room_id)
        else
          acc
        end
      end)

    Process.send_after(self(), :sweep_inactive_rooms, @sweep_interval_ms)
    broadcast_rooms(rooms)
    {:noreply, rooms}
  end

  def handle_info({:close_if_no_admin, room_id}, rooms) do
    rooms =
      if Map.has_key?(rooms, room_id) && admin_count(room_id) == 0 do
        close_room(rooms, room_id)
      else
        rooms
      end

    broadcast_rooms(rooms)
    {:noreply, rooms}
  end

  defp maybe_close_for_occupancy(rooms, room_id, phase) do
    cond do
      !Map.has_key?(rooms, room_id) ->
        rooms

      active_count(room_id) == 0 ->
        close_room(rooms, room_id)

      phase in [:standby, :loaded] && admin_count(room_id) == 0 ->
        close_room(rooms, room_id)

      phase == :podium && admin_count(room_id) == 0 ->
        Process.send_after(self(), {:close_if_no_admin, room_id}, @podium_close_after_ms)
        rooms

      true ->
        rooms
    end
  end

  defp reserve_player_slot(rooms, room_id, player_id) do
    with {:room, %Room{} = room} <- {:room, Map.get(rooms, room_id)},
         {:joinable, true} <- {:joinable, joinable?(room_id)},
         {:capacity, true} <- {:capacity, admitted_player_count(room, player_id) < @max_players} do
      room = %{
        room
        | player_colors: Map.put_new(room.player_colors, player_id, nil),
          updated_at: now_ms()
      }

      {:ok, Map.put(rooms, room_id, room)}
    else
      {:room, nil} -> {:error, :room_closed}
      {:joinable, false} -> {:error, :game_in_progress}
      {:capacity, false} -> {:error, :room_full}
    end
  end

  defp release_player_slot(rooms, room_id, player_id) do
    Map.update(rooms, room_id, nil, fn
      nil ->
        nil

      room ->
        %{room | player_colors: Map.delete(room.player_colors, player_id), updated_at: now_ms()}
    end)
    |> Enum.reject(fn {_room_id, room} -> is_nil(room) end)
    |> Map.new()
  end

  defp admit_player(rooms, room_id, player_id, _name, color) do
    with {:room, %Room{} = room} <- {:room, Map.get(rooms, room_id)},
         {:joinable, true} <- {:joinable, joinable?(room_id)},
         {:color, true} <- {:color, PlayerColors.valid?(color)},
         {:capacity, true} <- {:capacity, admitted_player_count(room, player_id) < @max_players},
         {:available, true} <- {:available, color_available?(room, player_id, color)} do
      room = %{
        room
        | player_colors: Map.put(room.player_colors, player_id, color),
          updated_at: now_ms()
      }

      {:ok, Map.put(rooms, room_id, room)}
    else
      {:room, nil} -> {:error, :room_closed}
      {:joinable, false} -> {:error, :game_in_progress}
      {:color, false} -> {:error, :invalid_color}
      {:capacity, false} -> {:error, :room_full}
      {:available, false} -> {:error, :color_taken}
    end
  end

  defp admitted_player_count(room, player_id),
    do: room.player_colors |> Map.delete(player_id) |> map_size()

  defp color_available?(room, player_id, color) do
    room.player_colors
    |> Map.delete(player_id)
    |> Map.values()
    |> Enum.all?(&(&1 != color))
  end

  defp touch_room_in_memory(rooms, room_id) do
    Map.update(rooms, room_id, nil, fn
      nil -> nil
      room -> %{room | updated_at: now_ms()}
    end)
    |> Enum.reject(fn {_room_id, room} -> is_nil(room) end)
    |> Map.new()
  end

  defp close_room(rooms, room_id) do
    case Map.pop(rooms, room_id) do
      {nil, rooms} ->
        rooms

      {room, rooms} ->
        Phoenix.PubSub.broadcast(LiveTrivia.PubSub, "room:#{room_id}", {:room_closed, room_id})
        DynamicSupervisor.terminate_child(LiveTrivia.RoomSupervisor, room.game_pid)
        rooms
    end
  end

  defp public_rooms(rooms) do
    rooms
    |> Map.values()
    |> Enum.map(fn room ->
      game_state = safe_game_state(room.id)

      %{
        id: room.id,
        name: room.name,
        admin_id: room.admin_id,
        phase: room_phase(game_state),
        round_label: round_label(game_state),
        joinable: joinable_state?(game_state),
        password_protected?: not is_nil(room.password_hash),
        player_count: max(player_count(room.id), map_size(room.player_colors)),
        admin_count: admin_count(room.id),
        updated_at: room.updated_at
      }
    end)
    |> Enum.sort_by(& &1.updated_at, :desc)
  end

  defp broadcast_rooms(rooms) do
    Phoenix.PubSub.broadcast(LiveTrivia.PubSub, @topic, {:rooms_updated, public_rooms(rooms)})
  end

  defp room_phase(game_state) do
    case game_state do
      %{phase: phase} -> phase
      _ -> :closed
    end
  end

  defp round_label(%{phase: phase, current_index: index, questions: questions})
       when phase in [:in_progress, :results] and length(questions) > 0 do
    "Round #{min(index + 1, length(questions))}/#{length(questions)}"
  end

  defp round_label(_game_state), do: nil

  defp joinable_state?(%{phase: phase}) when phase in [:standby, :loaded, :podium], do: true
  defp joinable_state?(_game_state), do: false

  defp safe_game_state(room_id) do
    LiveTrivia.Game.get_state(room_id)
  catch
    :exit, _reason -> nil
  end

  defp normalize_name(name, room_id) do
    name = name |> to_string() |> String.trim() |> String.slice(0, 40)
    if name == "", do: "Room #{String.upcase(room_id)}", else: name
  end

  defp password_credentials(password) do
    password = normalize_password(password)

    if password == "" do
      {nil, nil}
    else
      salt = :crypto.strong_rand_bytes(16)
      {hash_password(password, salt), salt}
    end
  end

  defp verify_password(%Room{password_hash: expected_hash, password_salt: salt}, password) do
    password_hash = password |> normalize_password() |> hash_password(salt)

    if Plug.Crypto.secure_compare(password_hash, expected_hash) do
      :ok
    else
      {:error, :invalid_password}
    end
  end

  defp normalize_password(password) do
    password
    |> to_string()
    |> String.trim()
    |> String.slice(0, 80)
  end

  defp hash_password(password, salt) do
    :crypto.hash(:sha256, [salt, password])
  end

  defp random_id do
    4
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp next_topic_id(rooms) do
    used_topic_ids = rooms |> Map.values() |> MapSet.new(& &1.topic_id)

    0..(@max_rooms - 1)
    |> Enum.find(&(Integer.to_string(&1, 16) not in used_topic_ids))
    |> Integer.to_string(16)
  end

  defp now_ms, do: System.system_time(:millisecond)
end
