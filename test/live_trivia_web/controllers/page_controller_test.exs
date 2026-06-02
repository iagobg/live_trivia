defmodule LiveTriviaWeb.LobbyLiveTest do
  use LiveTriviaWeb.ConnCase

  test "GET / renders the room lobby", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Live Trivia"
    assert html_response(conn, 200) =~ "Open Rooms"
    assert html_response(conn, 200) =~ "Create"
  end
end
