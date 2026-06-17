defmodule LiveTriviaWeb.UserSocket do
  use Phoenix.Socket

  channel "t:*", LiveTriviaWeb.TypingChannel
  channel "typing:*", LiveTriviaWeb.TypingChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
