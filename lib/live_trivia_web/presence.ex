defmodule LiveTriviaWeb.Presence do
  use Phoenix.Presence,
    otp_app: :live_trivia,
    pubsub_server: LiveTrivia.PubSub
end
