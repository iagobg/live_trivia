defmodule LiveTriviaWeb.PlayerOrbitComponent do
  use LiveTriviaWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="pointer-events-auto absolute flex -translate-x-1/2 -translate-y-1/2 flex-col items-center gap-1"
      style={orbit_style(@index, @count)}
    >
      <div class="relative">
        <div
          :if={@leading}
          class="absolute -inset-3 rounded-full blur-md"
          style={"background: radial-gradient(circle, #{@player.color}cc 0%, #{@player.color}55 45%, transparent 72%);"}
        />
        <div
          class={[
            "relative flex h-12 w-12 items-center justify-center rounded-full border-2 text-lg font-bold text-white transition-all",
            @leading && "scale-110",
            result_shadow(@guess_result)
          ]}
          style={player_avatar_style(@player, @guess_result, @leading)}
        >
          {String.first(@player.name) |> String.upcase()}
        </div>
      </div>
      <div class="text-center">
        <div
          class="rounded-full border px-2 py-0.5 text-xs font-semibold"
          style={"color: #{@player.color}; background-color: #{@player.color}22; border-color: #{@player.color}44;"}
        >
          {@player.name}
          <span :if={@player.player_id == @current_player_id} class="ml-1 text-gray-500">(you)</span>
        </div>
        <div class="mt-0.5 font-mono text-xs text-gray-500">
          {@score} pts
        </div>
      </div>
      <div
        :if={@typing_text != ""}
        class="absolute -bottom-8 left-1/2 -translate-x-1/2 whitespace-nowrap"
      >
        <div class="max-w-32 truncate rounded-lg border border-gray-700 bg-gray-800/90 px-2 py-1 text-xs text-gray-300">
          {@typing_text}
        </div>
      </div>
    </div>
    """
  end

  defp orbit_style(index, count) do
    angle = index / count * 2 * :math.pi() - :math.pi() / 2
    x = 50 + 24 * :math.cos(angle)
    y = 50 + 32 * :math.sin(angle)
    "left: #{x}%; top: #{y}%;"
  end

  defp result_color(:correct, _color), do: "#22c55e"
  defp result_color(:close, _color), do: "#eab308"
  defp result_color(:near, _color), do: "#f97316"
  defp result_color(:far, _color), do: "#ef4444"
  defp result_color(_result, color), do: color

  defp player_avatar_style(player, guess_result, true) do
    border = result_color(guess_result, player.color)

    "background-color: #{player.color}33; border-color: #{border}; box-shadow: 0 0 0 5px #{player.color}44, 0 0 34px #{player.color}dd;"
  end

  defp player_avatar_style(player, guess_result, _leading) do
    border = result_color(guess_result, player.color)
    "background-color: #{player.color}33; border-color: #{border};"
  end

  defp result_shadow(:correct), do: "shadow-[0_0_28px_rgba(34,197,94,0.8)]"
  defp result_shadow(:close), do: "shadow-[0_0_28px_rgba(234,179,8,0.8)]"
  defp result_shadow(:near), do: "shadow-[0_0_28px_rgba(249,115,22,0.8)]"
  defp result_shadow(:far), do: "shadow-[0_0_28px_rgba(239,68,68,0.8)]"
  defp result_shadow(_result), do: nil
end
