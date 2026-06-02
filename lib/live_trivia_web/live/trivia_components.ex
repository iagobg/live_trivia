defmodule LiveTriviaWeb.TriviaComponents do
  use Phoenix.Component

  attr :game_state, :map, required: true
  attr :players, :list, required: true
  attr :current_player_id, :any, default: nil
  slot :inner_block

  def game_stage(assigns) do
    ~H"""
    <div class="relative min-h-screen overflow-hidden bg-gray-950 text-white">
      <div class="absolute inset-0 opacity-30">
        <div
          :for={i <- 1..60}
          class="star"
          style={"--x: #{rem(i * 37, 100)}%; --y: #{rem(i * 53, 100)}%;"}
        />
      </div>

      <div class="relative z-10 flex min-h-screen items-center justify-center px-4 py-20">
        <.player_orbit
          players={@players}
          game_state={@game_state}
          current_player_id={@current_player_id}
        />
        <.central_hub game_state={@game_state} />
      </div>

      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :players, :list, required: true
  attr :game_state, :map, required: true
  attr :current_player_id, :any, default: nil

  def player_orbit(assigns) do
    assigns = assign(assigns, :count, max(length(assigns.players), 1))

    ~H"""
    <div class="pointer-events-none absolute inset-0">
      <div
        :for={{player, index} <- Enum.with_index(@players)}
        class="pointer-events-auto absolute flex -translate-x-1/2 -translate-y-1/2 flex-col items-center gap-1"
        style={orbit_style(index, @count)}
      >
        <div
          class={[
            "flex h-12 w-12 items-center justify-center rounded-full border-2 text-lg font-bold text-white transition-all",
            result_shadow(player.guess_result)
          ]}
          style={"background-color: #{player.color}33; border-color: #{result_color(player.guess_result, player.color)};"}
        >
          {String.first(player.name) |> String.upcase()}
        </div>
        <div class="text-center">
          <div
            class="rounded-full border px-2 py-0.5 text-xs font-semibold"
            style={"color: #{player.color}; background-color: #{player.color}22; border-color: #{player.color}44;"}
          >
            {player.name}
            <span :if={player.player_id == @current_player_id} class="ml-1 text-gray-500">(you)</span>
          </div>
          <div class="mt-0.5 font-mono text-xs text-gray-500">
            {Map.get(@game_state.player_scores, player.player_id, 0)} pts
          </div>
        </div>
        <div
          :if={player.typing_text != ""}
          class="absolute -bottom-8 left-1/2 -translate-x-1/2 whitespace-nowrap"
        >
          <div class="max-w-32 truncate rounded-lg border border-gray-700 bg-gray-800/90 px-2 py-1 text-xs text-gray-300">
            {player.typing_text}
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :game_state, :map, required: true

  def central_hub(assigns) do
    assigns =
      assigns
      |> assign(:current_question, current_question(assigns.game_state))
      |> assign(:time_left, time_left(assigns.game_state))
      |> assign(:available_score, available_score(assigns.game_state))

    ~H"""
    <div class="relative z-10 flex flex-col items-center justify-center">
      <div
        id="round-meter"
        phx-hook="RoundMeter"
        data-phase={@game_state.phase}
        data-start={@game_state.round_start_time}
        data-server-now={@game_state.server_now}
        data-round={@game_state.current_index}
        data-duration="30000"
        class="relative flex h-[280px] w-[280px] items-center justify-center"
      >
        <svg
          width="280"
          height="280"
          viewBox="0 0 280 280"
          class="pointer-events-none absolute inset-0 -rotate-90"
          aria-hidden="true"
        >
          <circle
            cx="140"
            cy="140"
            r="110"
            fill="none"
            stroke="rgba(255,255,255,0.08)"
            stroke-width="8"
          />
          <circle
            data-role="timer-progress"
            cx="140"
            cy="140"
            r="110"
            fill="none"
            stroke="#22c55e"
            stroke-width="8"
            stroke-linecap="round"
            stroke-dasharray="691.15 691.15"
            class={[
              "round-progress transition-[stroke] duration-300",
              @game_state.phase != :in_progress && "opacity-0"
            ]}
          />
        </svg>

        <div
          data-role="hub-shell"
          class={[
            "relative flex h-56 w-56 flex-col items-center justify-center rounded-full border-2 bg-gray-900 px-4 text-center shadow-2xl",
            @game_state.phase == :in_progress && @time_left <= 5 && "animate-pulse",
            if(@game_state.phase == :in_progress, do: "border-gray-700", else: "border-gray-800")
          ]}
        >
          <div :if={@game_state.phase == :standby} class="flex flex-col items-center gap-2">
            <div class="text-5xl font-black text-indigo-300">?</div>
            <div class="text-sm font-medium text-gray-400">Waiting for quiz</div>
          </div>

          <div :if={@game_state.phase == :loaded} class="flex flex-col items-center gap-2">
            <div class="text-4xl font-black text-green-300">OK</div>
            <div class="text-sm font-medium text-indigo-300">
              {length(@game_state.questions)} questions loaded
            </div>
            <div class="text-xs text-gray-500">Waiting to start</div>
          </div>

          <div :if={@game_state.phase == :in_progress} class="flex flex-col items-center gap-1">
            <div
              data-role="timer-value"
              class={["text-5xl font-black tabular-nums", timer_color(@time_left)]}
            >
              {ceil(@time_left)}
            </div>
            <div class="text-xs uppercase tracking-widest text-gray-500">seconds</div>
            <div data-role="score-value" class="mt-1 text-2xl font-bold text-amber-400">
              {@available_score}
            </div>
            <div class="text-xs uppercase tracking-widest text-gray-500">pts available</div>
            <div class="mt-1 text-xs text-gray-600">
              Q {@game_state.current_index + 1}/{length(@game_state.questions)}
            </div>
          </div>

          <div :if={@game_state.phase == :results} class="flex flex-col items-center gap-1">
            <div class="text-sm font-bold text-white">
              {result_title(@game_state.round_winner)}
            </div>
            <div :if={@game_state.round_winner} class="text-xs font-semibold text-yellow-400">
              {@game_state.round_winner.player_name}
            </div>
            <div :if={@current_question} class="text-sm font-bold text-white">
              Answer: {@current_question.answer}
            </div>
            <div class="mt-1 text-xs text-gray-500">Next round soon</div>
          </div>

          <div :if={@game_state.phase == :podium} class="flex flex-col items-center gap-2">
            <div class="text-5xl font-black text-amber-300">#1</div>
            <div class="text-sm font-medium text-gray-400">Final leaderboard</div>
          </div>
        </div>
      </div>

      <div :if={@current_question} class="mt-6 max-w-sm text-center">
        <div class="rounded-xl border border-gray-700 bg-gray-900/80 px-5 py-3">
          <p class="text-base font-semibold leading-snug text-white">{@current_question.question}</p>
        </div>
      </div>

      <div
        :if={@current_question && @game_state.phase in [:in_progress, :results]}
        class="mt-3 flex max-w-sm flex-wrap justify-center gap-2"
      >
        <div
          :for={{hint, index} <- Enum.with_index(@current_question.hints)}
          class={[
            "rounded-lg border px-3 py-1.5 text-xs font-medium",
            if(index < @game_state.revealed_hints,
              do: "border-indigo-500 bg-indigo-600/80 text-white",
              else: "border-gray-700 bg-gray-800/50 text-gray-600"
            )
          ]}
        >
          <%= if index < @game_state.revealed_hints do %>
            {hint}
          <% else %>
            Hint {index + 1}
          <% end %>
        </div>
      </div>

      <div
        :if={@game_state.closest_guess}
        class="mt-3 rounded-xl border border-gray-700 bg-gray-900/60 px-4 py-2 text-center text-xs"
      >
        <span class="text-gray-500">Closest so far: </span>
        <span class="font-semibold text-yellow-400">{@game_state.closest_guess.player_name}</span>
        <span class="text-gray-500"> - "{@game_state.closest_guess.guess_text}"</span>
        <span class="text-gray-600"> (d={@game_state.closest_guess.distance})</span>
      </div>
    </div>
    """
  end

  attr :game_state, :map, required: true
  attr :players, :list, required: true

  def podium(assigns) do
    assigns = assign(assigns, :leaders, leaders(assigns.game_state, assigns.players))

    ~H"""
    <div
      id="podium-screen"
      phx-hook="PodiumReveal"
      class="relative min-h-screen overflow-hidden bg-gray-950 px-4 py-12 text-white"
    >
      <div class="pointer-events-none fixed inset-0 overflow-hidden">
        <div
          :for={i <- 1..40}
          class="victory-confetti"
          style={
            "--x: #{rem(i * 47, 100)}%; --y: #{rem(i * 31, 100)}%; --size: #{4 + rem(i * 7, 8)}px; --delay: #{rem(i * 11, 20) / 10}s; --duration: #{1 + rem(i * 13, 20) / 10}s; --color: #{confetti_color(i)};"
          }
        />
      </div>

      <div class="mx-auto flex min-h-[calc(100vh-6rem)] w-full max-w-lg flex-col justify-center">
        <div class="mb-8 text-center">
          <div class="text-5xl font-black text-amber-300">TROPHY</div>
          <h1 class="mt-3 text-4xl font-black">Final Leaderboard</h1>
          <p class="mt-2 text-gray-400">Game over</p>
        </div>

        <div class="flex flex-col gap-3">
          <div
            :for={{entry, index} <- Enum.with_index(@leaders)}
            data-role="podium-row"
            data-index={index}
            class={[
              "translate-x-8 opacity-0 transition-all duration-500",
              "flex items-center gap-4 rounded-xl border px-5 py-4",
              podium_row_class(index)
            ]}
          >
            <div class="w-10 text-center text-xl font-black">{rank_label(index)}</div>
            <div
              class="flex h-10 w-10 items-center justify-center rounded-full border-2 text-lg font-bold text-white"
              style={"background-color: #{entry.color}33; border-color: #{entry.color};"}
            >
              {String.first(entry.name) |> String.upcase()}
            </div>
            <div class="flex-1 font-bold">{entry.name}</div>
            <div class="text-right">
              <div class="text-xl font-black text-amber-300">{entry.score}</div>
              <div class="text-xs text-gray-500">points</div>
            </div>
          </div>

          <div :if={@leaders == []} class="py-8 text-center text-gray-500">No scores recorded</div>
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

  defp result_shadow(:correct), do: "shadow-[0_0_28px_rgba(34,197,94,0.8)]"
  defp result_shadow(:close), do: "shadow-[0_0_28px_rgba(234,179,8,0.8)]"
  defp result_shadow(:near), do: "shadow-[0_0_28px_rgba(249,115,22,0.8)]"
  defp result_shadow(:far), do: "shadow-[0_0_28px_rgba(239,68,68,0.8)]"
  defp result_shadow(_result), do: nil

  defp current_question(%{phase: phase, questions: questions, current_index: index})
       when phase in [:in_progress, :results] do
    Enum.at(questions, index)
  end

  defp current_question(_state), do: nil

  defp time_left(%{phase: :in_progress, round_start_time: start}) when is_integer(start) do
    max(0, 30 - (System.system_time(:millisecond) - start) / 1_000)
  end

  defp time_left(_state), do: 0

  defp available_score(%{phase: :in_progress, round_start_time: start}) when is_integer(start) do
    elapsed = (System.system_time(:millisecond) - start) / 1_000
    max(250, round(1_000 - 30 * max(0, elapsed - 5)))
  end

  defp available_score(_state), do: 1_000

  defp timer_color(time_left) when time_left <= 5, do: "text-red-500"
  defp timer_color(time_left) when time_left <= 14, do: "text-yellow-400"
  defp timer_color(_time_left), do: "text-green-500"

  defp result_title(%{is_consolation: true}), do: "Closest Guess"
  defp result_title(%{is_consolation: false}), do: "Correct!"
  defp result_title(_winner), do: "Time's Up"

  defp leaders(game_state, players) do
    game_state.player_scores
    |> Enum.map(fn {player_id, score} ->
      player = Enum.find(players, &(&1.player_id == player_id))

      %{
        player_id: player_id,
        name: (player && player.name) || String.slice(player_id, 0, 8),
        color: (player && player.color) || "#888888",
        score: score
      }
    end)
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(10)
  end

  defp rank_label(0), do: "1"
  defp rank_label(1), do: "2"
  defp rank_label(2), do: "3"
  defp rank_label(index), do: "##{index + 1}"

  defp podium_row_class(0), do: "border-yellow-600/50 bg-yellow-900/30"
  defp podium_row_class(1), do: "border-gray-500/50 bg-gray-700/30"
  defp podium_row_class(2), do: "border-orange-700/50 bg-orange-900/30"
  defp podium_row_class(_index), do: "border-gray-700/30 bg-gray-800/30"

  defp confetti_color(index) do
    Enum.at(["#FF6B6B", "#4ECDC4", "#FFEAA7", "#DDA0DD", "#45B7D1"], rem(index, 5))
  end
end
