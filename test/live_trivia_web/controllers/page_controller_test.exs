defmodule LiveTriviaWeb.PlayerLiveTest do
  use LiveTriviaWeb.ConnCase

  test "GET / renders the join screen", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Live Trivia"
    assert html_response(conn, 200) =~ "Join Game"
  end
end
