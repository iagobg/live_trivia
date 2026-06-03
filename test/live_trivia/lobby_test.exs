defmodule LiveTrivia.LobbyTest do
  use ExUnit.Case, async: false

  alias LiveTrivia.Lobby
  alias LiveTrivia.PlayerColors

  test "admits players with unique colors" do
    room = create_room!()
    [color | _] = PlayerColors.all()

    assert :ok = Lobby.reserve_player(room.id, "player-1")
    assert :ok = Lobby.join_room(room.id, "player-1", "Player 1", color)
    assert [^color] = Lobby.taken_player_colors(room.id, "player-2")

    on_exit(fn -> Lobby.close_room(room.id) end)
  end

  test "rejects a duplicate color" do
    room = create_room!()
    [color | _] = PlayerColors.all()

    assert :ok = Lobby.reserve_player(room.id, "player-1")
    assert :ok = Lobby.reserve_player(room.id, "player-2")
    assert :ok = Lobby.join_room(room.id, "player-1", "Player 1", color)
    assert {:error, :color_taken} = Lobby.join_room(room.id, "player-2", "Player 2", color)

    on_exit(fn -> Lobby.close_room(room.id) end)
  end

  test "rejects players above the room limit" do
    room = create_room!()

    PlayerColors.all()
    |> Enum.with_index(1)
    |> Enum.each(fn {color, index} ->
      assert :ok = Lobby.reserve_player(room.id, "player-#{index}")
      assert :ok = Lobby.join_room(room.id, "player-#{index}", "Player #{index}", color)
    end)

    assert {:error, :room_full} = Lobby.reserve_player(room.id, "player-17")

    on_exit(fn -> Lobby.close_room(room.id) end)
  end

  test "reserves a player slot before profile selection" do
    room = create_room!()

    1..16
    |> Enum.each(fn index ->
      assert :ok = Lobby.reserve_player(room.id, "player-#{index}")
    end)

    assert {:error, :room_full} = Lobby.reserve_player(room.id, "player-17")

    Lobby.leave_room(room.id, "player-8")
    assert :ok = Lobby.reserve_player(room.id, "player-17")

    on_exit(fn -> Lobby.close_room(room.id) end)
  end

  test "verifies room passwords without exposing the password" do
    {:ok, room} = Lobby.create_room("Protected room", "admin-password", "secret")

    assert :ok = Lobby.verify_room_password(room.id, "secret")
    assert {:error, :invalid_password} = Lobby.verify_room_password(room.id, "wrong")

    public_room = Enum.find(Lobby.list_rooms(), &(&1.id == room.id))
    assert public_room.password_protected?
    refute Map.has_key?(public_room, :password_hash)
    refute Map.has_key?(public_room, :password_salt)

    on_exit(fn -> Lobby.close_room(room.id) end)
  end

  test "rooms without passwords do not require verification" do
    room = create_room!()

    assert :ok = Lobby.verify_room_password(room.id, "")

    public_room = Enum.find(Lobby.list_rooms(), &(&1.id == room.id))
    refute public_room.password_protected?

    on_exit(fn -> Lobby.close_room(room.id) end)
  end

  defp create_room! do
    {:ok, room} = Lobby.create_room("Test room", "admin-#{System.unique_integer([:positive])}")
    room
  end
end
