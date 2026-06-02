defmodule LiveTriviaWeb.PlayerSession do
  import Plug.Conn

  @colors [
    "#FF6B6B",
    "#4ECDC4",
    "#45B7D1",
    "#96CEB4",
    "#FFEAA7",
    "#DDA0DD",
    "#98D8C8",
    "#F7DC6F",
    "#BB8FCE",
    "#85C1E9",
    "#F0B27A",
    "#82E0AA"
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> ensure_session_value("player_id", &random_id/0)
    |> ensure_session_value("player_color", &random_color/0)
  end

  defp ensure_session_value(conn, key, generator) do
    case get_session(conn, key) do
      nil -> put_session(conn, key, generator.())
      _value -> conn
    end
  end

  defp random_id do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp random_color, do: Enum.random(@colors)
end
