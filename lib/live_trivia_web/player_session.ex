defmodule LiveTriviaWeb.PlayerSession do
  import Plug.Conn

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

  defp random_color, do: Enum.random(LiveTrivia.PlayerColors.all())
end
