defmodule LiveTrivia.GameTest do
  use ExUnit.Case, async: false

  alias LiveTrivia.Game
  alias LiveTrivia.Lobby

  @questions [
    %{
      question: "Capital of France",
      answer: "Paris",
      hints: ["France", "P", "Pa", "City", "Pair"]
    },
    %{question: "Capital of Japan", answer: "Tokyo", hints: ["Japan", "T", "To", "Edo", "City"]}
  ]

  test "ignores stale timer messages from previous round lifecycles" do
    room = create_room!()
    track_admin!(room)

    assert :ok = Game.load_questions(room.id, @questions)
    assert :ok = Game.start_quiz(room.id)

    assert %{round_id: round_id} = :sys.get_state(room.game_pid)

    assert :ok = Game.load_questions(room.id, @questions)
    assert :ok = Game.start_quiz(room.id)

    send(room.game_pid, {:hint, 0, round_id, 0})
    send(room.game_pid, {:round_timeout, 0, round_id})
    send(room.game_pid, {:advance_round, 0, round_id})

    _ = :sys.get_state(room.game_pid)
    state = Game.get_state(room.id)

    assert state.phase == :in_progress
    assert state.current_index == 0
    assert state.revealed_hints == 0

    on_exit(fn -> Lobby.close_room(room.id) end)
  end

  defp create_room! do
    {:ok, room} = Lobby.create_room("Game test", "admin-#{System.unique_integer([:positive])}")
    room
  end

  defp track_admin!(room) do
    {:ok, _ref} =
      LiveTriviaWeb.Presence.track(self(), "admins:#{room.id}", room.admin_id, %{
        admin_id: room.admin_id
      })
  end
end
