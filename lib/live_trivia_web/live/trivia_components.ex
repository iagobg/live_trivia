defmodule LiveTriviaWeb.TriviaComponents do
  use LiveTriviaWeb, :html

  alias LiveTriviaWeb.ResultColors
  alias LiveTriviaWeb.TypingBubble

  attr :game_state, :map, required: true
  attr :players, :list, required: true
  attr :current_player_id, :any, default: nil
  attr :typing_by_player, :map, default: %{}
  attr :guess_results, :map, default: %{}
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

      <div class="relative z-10 flex min-h-[100svh] items-start justify-center px-4 pb-36 pt-16 sm:min-h-screen sm:items-center sm:py-20">
        <.player_orbit
          players={@players}
          game_state={@game_state}
          current_player_id={@current_player_id}
          typing_by_player={@typing_by_player}
          guess_results={@guess_results}
        />
        <.central_hub game_state={@game_state} players={@players} />
        <.mobile_player_roster
          players={@players}
          game_state={@game_state}
          current_player_id={@current_player_id}
          guess_results={@guess_results}
        />
        <.mobile_typing_bubbles players={@players} typing_by_player={@typing_by_player} />
      </div>

      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :players, :list, required: true
  attr :game_state, :map, required: true
  attr :current_player_id, :any, default: nil
  attr :guess_results, :map, default: %{}

  def mobile_player_roster(assigns) do
    ~H"""
    <div class="pointer-events-none absolute inset-x-3 top-3 z-20 sm:hidden" aria-hidden="true">
      <div class="grid max-w-[calc(100%-5.5rem)] grid-cols-8 gap-1.5">
        <div
          :for={player <- Enum.take(@players, 16)}
          class="flex min-w-0 flex-col items-center gap-0.5"
        >
          <div
            class={[
              "flex h-8 w-8 items-center justify-center rounded-full border-2 text-xs font-black text-white shadow-lg",
              Map.get(@guess_results, player.player_id) == :correct && "scale-110"
            ]}
            style={mobile_player_avatar_style(player, Map.get(@guess_results, player.player_id))}
          >
            {String.first(player.name) |> String.upcase()}
          </div>
          <div class={[
            "max-w-10 truncate rounded-full px-1 text-[0.55rem] font-bold leading-3",
            player.player_id == @current_player_id && "bg-white/15 text-white",
            player.player_id != @current_player_id && "text-gray-400"
          ]}>
            {Map.get(@game_state.player_scores, player.player_id, 0)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :players, :list, required: true
  attr :typing_by_player, :map, default: %{}

  def mobile_typing_bubbles(assigns) do
    assigns =
      assign(
        assigns,
        :typing_players,
        Enum.filter(
          assigns.players,
          &(TypingBubble.visible_count(Map.get(assigns.typing_by_player, &1.player_id)) > 0)
        )
      )

    ~H"""
    <div class="pointer-events-none absolute inset-0 z-20 sm:hidden" aria-hidden="true">
      <div
        :for={index <- 0..15}
        class="absolute h-44 w-24"
        style={mobile_bubble_slot_style(index)}
      >
        <div :if={player = Enum.at(@typing_players, index)} class="relative h-full w-full">
          <TypingBubble.guess_burst
            :for={
              {bubble, bubble_index} <-
                Enum.with_index(
                  TypingBubble.submitted_bubbles(Map.get(@typing_by_player, player.player_id))
                )
            }
            id={"mobile-submitted-bubble-#{player.player_id}-#{bubble.id}"}
            player={player}
            text={TypingBubble.text(bubble)}
            class={[
              "inset-x-0 top-0 w-full text-[0.68rem]",
              mobile_submitted_bubble_z_index(bubble_index)
            ]}
          />
          <TypingBubble.typing_bubble
            :if={TypingBubble.active_text(Map.get(@typing_by_player, player.player_id)) != ""}
            id={"mobile-live-bubble-#{player.player_id}"}
            player={player}
            text={TypingBubble.active_text(Map.get(@typing_by_player, player.player_id))}
            class="absolute left-0 top-0 z-[60] w-full max-w-full rounded-full px-2.5 py-1.5 text-center text-[0.68rem] font-bold"
          />
        </div>
      </div>
    </div>
    """
  end

  attr :players, :list, required: true
  attr :game_state, :map, required: true
  attr :current_player_id, :any, default: nil
  attr :typing_by_player, :map, default: %{}
  attr :guess_results, :map, default: %{}

  def player_orbit(assigns) do
    assigns = assign(assigns, :count, max(length(assigns.players), 1))

    ~H"""
    <div class="pointer-events-none absolute inset-0 hidden sm:block">
      <.live_component
        :for={{player, index} <- Enum.with_index(@players)}
        module={LiveTriviaWeb.PlayerOrbitComponent}
        id={"player-#{player.player_id}"}
        player={player}
        index={index}
        count={@count}
        current_player_id={@current_player_id}
        score={Map.get(@game_state.player_scores, player.player_id, 0)}
        guess_result={Map.get(@guess_results, player.player_id)}
        typing={Map.get(@typing_by_player, player.player_id)}
        leading={
          (@game_state.closest_guess && @game_state.closest_guess.player_id == player.player_id) ||
            false
        }
      />
    </div>
    """
  end

  attr :game_state, :map, required: true
  attr :players, :list, required: true

  def central_hub(assigns) do
    assigns =
      assigns
      |> assign(:current_question, current_question(assigns.game_state))
      |> assign(:round_label, round_label(assigns.game_state))
      |> assign(:closest_color, closest_player_color(assigns.game_state, assigns.players))
      |> assign(
        :visible_hints,
        visible_hints(current_question(assigns.game_state), assigns.game_state)
      )

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
        class="relative flex h-[300px] w-[300px] items-center justify-center sm:h-[360px] sm:w-[360px]"
      >
        <svg
          width="360"
          height="360"
          viewBox="0 0 360 360"
          class="pointer-events-none absolute inset-0 h-full w-full -rotate-90"
          aria-hidden="true"
        >
          <circle
            cx="180"
            cy="180"
            r="160"
            fill="none"
            stroke="rgba(255,255,255,0.08)"
            stroke-width="8"
          />
          <circle
            data-role="timer-progress"
            cx="180"
            cy="180"
            r="160"
            fill="none"
            stroke="#22c55e"
            stroke-width="8"
            stroke-linecap="round"
            stroke-dasharray="1005.31 1005.31"
            class={[
              "round-progress transition-[stroke] duration-300",
              @game_state.phase != :in_progress && "opacity-0"
            ]}
          />
        </svg>

        <div
          data-role="hub-shell"
          class={[
            "relative flex h-[260px] w-[260px] flex-col items-center justify-center rounded-full border-2 bg-gray-900 px-6 py-6 text-center shadow-2xl sm:h-80 sm:w-80 sm:px-8 sm:py-8",
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

          <div
            :if={@game_state.phase == :in_progress}
            class="flex h-full w-full -translate-y-2 flex-col items-center justify-center gap-2"
          >
            <div
              :if={@round_label}
              class="rounded-full border border-indigo-500/40 bg-indigo-500/15 px-3 py-1 text-[0.65rem] font-black uppercase tracking-[0.12em] text-indigo-100"
            >
              Round {@round_label}
            </div>

            <div :if={@current_question} class="w-full">
              <p class="mx-auto line-clamp-2 max-w-48 text-sm font-bold leading-tight text-white sm:max-w-56">
                {@current_question.question}
              </p>
            </div>

            <div class="grid w-full grid-cols-2 items-center gap-2">
              <div>
                <div
                  data-role="timer-value"
                  class="text-3xl font-black leading-none text-green-500 tabular-nums sm:text-4xl"
                >
                  30
                </div>
                <div class="mt-0.5 text-[0.62rem] uppercase tracking-widest text-gray-500">
                  seconds
                </div>
              </div>
              <div>
                <div
                  data-role="score-value"
                  class="text-xl font-black leading-none text-amber-400 sm:text-2xl"
                >
                  1000
                </div>
                <div class="mt-0.5 text-[0.62rem] uppercase tracking-widest text-gray-500">
                  pts
                </div>
              </div>
            </div>

            <div class="grid h-[4.5rem] w-full grid-rows-3 gap-1 overflow-hidden">
              <div
                :for={{hint, index} <- Enum.with_index(@visible_hints)}
                id={"hint-ticker-#{@game_state.current_index}-#{index}"}
                phx-hook="HintTicker"
                class="hint-ticker flex h-5 items-center justify-center overflow-hidden rounded-md border border-indigo-500/50 bg-indigo-600/70 px-2 text-center text-[0.66rem] font-semibold leading-none text-white"
              >
                <span class="hint-ticker-content">{hint}</span>
              </div>
            </div>

            <div class="flex h-8 w-full items-center justify-center">
              <div
                :if={@game_state.closest_guess}
                class="max-w-full truncate rounded-full border px-3 py-1 text-xs font-black"
                style={"border-color: #{@closest_color}; color: #{@closest_color}; background: #{@closest_color}18; box-shadow: 0 0 18px #{@closest_color}28;"}
              >
                {@game_state.closest_guess.guess_text} ({@game_state.closest_guess.distance})
              </div>
            </div>
          </div>

          <div
            :if={@game_state.phase == :results}
            class="flex h-full w-full flex-col items-center justify-center gap-2"
          >
            <div
              :if={@round_label}
              class="rounded-full border border-indigo-500/40 bg-indigo-500/15 px-3 py-1 text-[0.65rem] font-black uppercase tracking-[0.12em] text-indigo-100"
            >
              Round {@round_label}
            </div>
            <div class="text-base font-black text-white">
              {result_title(@game_state.round_winner)}
            </div>
            <div
              :if={@game_state.round_winner}
              class="text-sm font-black"
              style={"color: #{winner_color(@game_state.round_winner, @players)};"}
            >
              {@game_state.round_winner.player_name} +{@game_state.round_winner.score}
            </div>
            <div
              :if={@current_question}
              class="w-full rounded-lg border border-green-600/50 bg-green-900/40 px-3 py-2"
            >
              <div class="text-[0.58rem] font-black uppercase tracking-[0.16em] text-green-300">
                Answer
              </div>
              <div class="mt-0.5 truncate text-sm font-black text-white">
                {@current_question.answer}
              </div>
            </div>
            <div class="text-xs text-gray-500">Next round soon</div>
          </div>

          <div :if={@game_state.phase == :podium} class="flex flex-col items-center gap-2">
            <div class="text-5xl font-black text-amber-300">#1</div>
            <div class="text-sm font-medium text-gray-400">Final leaderboard</div>
          </div>
        </div>
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
          <img src={~p"/images/trophy.png"} alt="Trophy" class="mx-auto h-24 w-24 object-contain" />
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

  defp current_question(%{phase: phase, questions: questions, current_index: index})
       when phase in [:in_progress, :results] do
    Enum.at(questions, index)
  end

  defp current_question(_state), do: nil

  defp result_title(%{is_consolation: true}), do: "Closest Guess"
  defp result_title(%{is_consolation: false}), do: "Correct!"
  defp result_title(_winner), do: "Time's Up"

  defp round_label(%{phase: phase, questions: questions, current_index: index})
       when phase in [:in_progress, :results] and length(questions) > 0 do
    "#{min(index + 1, length(questions))}/#{length(questions)}"
  end

  defp round_label(_game_state), do: nil

  defp closest_player_color(%{closest_guess: %{player_id: player_id}}, players) do
    player = Enum.find(players, &(&1.player_id == player_id))
    (player && player.color) || "#facc15"
  end

  defp closest_player_color(_game_state, _players), do: "#facc15"

  defp winner_color(%{player_id: player_id}, players) do
    player = Enum.find(players, &(&1.player_id == player_id))
    (player && player.color) || "#facc15"
  end

  defp winner_color(_winner, _players), do: "#facc15"

  defp visible_hints(nil, _game_state), do: []

  defp visible_hints(%{hints: hints}, %{revealed_hints: revealed_hints}) do
    hints
    |> Enum.take(revealed_hints)
    |> Enum.take(-3)
  end

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

  defp mobile_bubble_slot_style(index) do
    {left, top} =
      Enum.at(
        [
          {6, 12},
          {64, 9},
          {12, 26},
          {70, 25},
          {4, 43},
          {74, 44},
          {13, 60},
          {66, 62},
          {33, 8},
          {42, 24},
          {31, 58},
          {45, 72},
          {8, 76},
          {72, 78},
          {24, 38},
          {57, 48}
        ],
        index
      )

    "left: #{left}%; top: #{top}%;"
  end

  defp mobile_submitted_bubble_z_index(index) do
    ["z-10", "z-20", "z-30", "z-40", "z-50"]
    |> Enum.at(index, "z-10")
  end

  defp mobile_player_avatar_style(player, guess_result) do
    border = ResultColors.result_color(guess_result, player.color)

    "background-color: #{player.color}33; border-color: #{border}; box-shadow: 0 0 16px #{player.color}66;"
  end
end
