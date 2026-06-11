defmodule LiveTriviaWeb.TypingQueue do
  import Phoenix.Component, only: [assign: 3]

  alias LiveTriviaWeb.TypingBubble

  @flush_ms 33

  def queue(socket, update) do
    pending = [update | Map.get(socket.private, :pending_typing_updates, [])]
    flush_scheduled? = Map.get(socket.private, :typing_flush_scheduled?, false)

    socket = put_private(socket, :pending_typing_updates, pending)

    if flush_scheduled? do
      socket
    else
      Process.send_after(self(), :flush_typing_updates, @flush_ms)
      put_private(socket, :typing_flush_scheduled?, true)
    end
  end

  def flush(socket) do
    updates =
      socket.private
      |> Map.get(:pending_typing_updates, [])
      |> Enum.reverse()

    {typing_by_player, guess_results} =
      TypingBubble.apply_updates(
        socket.assigns.typing_by_player,
        socket.assigns.guess_results,
        updates
      )

    socket
    |> put_private(:pending_typing_updates, [])
    |> put_private(:typing_flush_scheduled?, false)
    |> assign(:typing_by_player, typing_by_player)
    |> assign(:guess_results, guess_results)
  end

  defp put_private(socket, key, value) do
    %{socket | private: Map.put(socket.private, key, value)}
  end
end
