defmodule LiveTrivia.Game do
  use GenServer

  @topic "game"
  @hint_times [5, 10, 15, 20, 25]
  @round_duration_ms 30_000
  @results_duration_ms 3_000

  defmodule State do
    defstruct phase: :standby,
              questions: [],
              current_index: 0,
              round_start_time: nil,
              revealed_hints: 0,
              player_scores: %{},
              closest_guess: nil,
              round_winner: nil,
              round_id: 0,
              timer_ref: nil,
              hint_refs: []
  end

  def child_spec(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    %{id: {__MODULE__, room_id}, start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    GenServer.start_link(__MODULE__, %State{}, name: via(room_id))
  end

  def subscribe(room_id), do: Phoenix.PubSub.subscribe(LiveTrivia.PubSub, topic(room_id))
  def get_state(room_id), do: GenServer.call(via(room_id), :get_state)
  def load_questions(room_id, questions), do: call(room_id, {:load_questions, questions})
  def start_quiz(room_id), do: call(room_id, :start_quiz)
  def next_round(room_id), do: call(room_id, :next_round)
  def force_reset(room_id), do: call(room_id, :force_reset)

  def submit_guess(room_id, player_id, player_name, guess_text),
    do: call(room_id, {:submit_guess, player_id, player_name, guess_text})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, public_state(state), state}

  def handle_call({:load_questions, questions}, _from, state) do
    touch_room()

    state =
      state
      |> cancel_timers()
      |> Map.merge(%State{
        phase: :loaded,
        questions: questions,
        current_index: 0,
        round_id: state.round_id + 1,
        player_scores: %{}
      })

    broadcast(state)
    {:reply, :ok, state}
  end

  def handle_call(:start_quiz, _from, %{phase: :loaded, questions: [_ | _]} = state) do
    touch_room()
    state = start_round(%{state | current_index: 0})
    broadcast(state)
    {:reply, :ok, state}
  end

  def handle_call(:start_quiz, _from, state), do: {:reply, :ignored, state}

  def handle_call(:next_round, _from, %{phase: phase} = state)
      when phase in [:in_progress, :results] do
    touch_room()
    state = advance_round(state, state.current_index)
    broadcast(state)
    {:reply, :ok, state}
  end

  def handle_call(:next_round, _from, state), do: {:reply, :ignored, state}

  def handle_call(:force_reset, _from, state) do
    touch_room()
    cancel_timers(state)
    state = %State{round_id: state.round_id + 1}
    broadcast(state)
    {:reply, :ok, state}
  end

  def handle_call(
        {:submit_guess, _player_id, _player_name, _guess_text},
        _from,
        %{phase: phase} = state
      )
      when phase != :in_progress,
      do: {:reply, nil, state}

  def handle_call({:submit_guess, player_id, player_name, guess_text}, _from, state) do
    touch_room()
    question = Enum.at(state.questions, state.current_index)
    distance = levenshtein(normalize(guess_text), normalize(question.answer))
    result = guess_result(distance)
    now = now_ms()

    closest_guess =
      closest_guess(state.closest_guess, %{
        player_id: player_id,
        player_name: player_name,
        distance: distance,
        guess_text: guess_text,
        submitted_at: now
      })

    {reply, state} =
      if distance == 0 do
        score = calc_score(state.round_start_time)
        cancel_refs([state.timer_ref | state.hint_refs])

        state = %{
          state
          | phase: :results,
            player_scores: Map.update(state.player_scores, player_id, score, &(&1 + score)),
            closest_guess: closest_guess,
            round_winner: %{
              player_id: player_id,
              player_name: player_name,
              score: score,
              is_consolation: false
            },
            timer_ref: schedule_advance(state.current_index, state.round_id),
            hint_refs: []
        }

        {%{result: result, score: score, distance: distance}, state}
      else
        state = %{
          state
          | closest_guess: closest_guess
        }

        {%{result: result, distance: distance}, state}
      end

    broadcast(state)
    {:reply, reply, state}
  end

  @impl true
  def handle_info(
        {:hint, round_index, round_id, hint_index},
        %{phase: :in_progress, current_index: round_index, round_id: round_id} = state
      ) do
    state = %{state | revealed_hints: max(state.revealed_hints, hint_index + 1)}
    broadcast(state)
    {:noreply, state}
  end

  def handle_info(
        {:round_timeout, round_index, round_id},
        %{phase: :in_progress, current_index: round_index, round_id: round_id} = state
      ) do
    {scores, winner} =
      case {state.closest_guess, state.round_winner} do
        {%{player_id: player_id, player_name: player_name}, nil} ->
          {Map.update(state.player_scores, player_id, 200, &(&1 + 200)),
           %{player_id: player_id, player_name: player_name, score: 200, is_consolation: true}}

        _ ->
          {state.player_scores, state.round_winner}
      end

    state = %{
      state
      | phase: :results,
        player_scores: scores,
        round_winner: winner,
        timer_ref: schedule_advance(round_index, round_id),
        hint_refs: []
    }

    broadcast(state)
    {:noreply, state}
  end

  def handle_info({:advance_round, round_index, round_id}, state) do
    state = advance_round(state, round_index, round_id)
    broadcast(state)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp start_round(state) do
    state = cancel_timers(state)
    round_id = state.round_id + 1

    hint_refs =
      Enum.with_index(@hint_times, fn seconds, index ->
        Process.send_after(self(), {:hint, state.current_index, round_id, index}, seconds * 1_000)
      end)

    %{
      state
      | phase: :in_progress,
        round_id: round_id,
        round_start_time: now_ms(),
        revealed_hints: 0,
        closest_guess: nil,
        round_winner: nil,
        timer_ref:
          Process.send_after(
            self(),
            {:round_timeout, state.current_index, round_id},
            @round_duration_ms
          ),
        hint_refs: hint_refs
    }
  end

  defp advance_round(state, round_index), do: advance_round(state, round_index, state.round_id)

  defp advance_round(
         %{current_index: current_index, round_id: round_id} = state,
         current_index,
         round_id
       ) do
    next_index = current_index + 1

    if next_index >= length(state.questions) do
      state
      |> cancel_timers()
      |> Map.merge(%State{
        phase: :podium,
        questions: state.questions,
        current_index: state.current_index,
        round_id: state.round_id,
        player_scores: state.player_scores
      })
    else
      start_round(%{state | current_index: next_index})
    end
  end

  defp advance_round(state, _stale_round, _stale_round_id), do: state

  defp schedule_advance(round_index, round_id),
    do: Process.send_after(self(), {:advance_round, round_index, round_id}, @results_duration_ms)

  defp cancel_timers(state) do
    cancel_refs([state.timer_ref | state.hint_refs])
    %{state | timer_ref: nil, hint_refs: []}
  end

  defp cancel_refs(refs) do
    Enum.each(List.wrap(refs), fn
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end)

    []
  end

  defp public_state(state) do
    state
    |> Map.take([
      :phase,
      :questions,
      :current_index,
      :round_start_time,
      :revealed_hints,
      :player_scores,
      :closest_guess,
      :round_winner
    ])
    |> Map.put(:server_now, now_ms())
  end

  defp calc_score(round_start_time) do
    elapsed = (now_ms() - round_start_time) / 1_000
    max(250, round(1_000 - 30 * max(0, elapsed - 5)))
  end

  defp closest_guess(nil, guess), do: guess

  defp closest_guess(current, %{distance: distance, submitted_at: submitted_at} = guess) do
    if distance < current.distance or
         (distance == current.distance and submitted_at < current.submitted_at),
       do: guess,
       else: current
  end

  defp guess_result(0), do: :correct
  defp guess_result(distance) when distance <= 2, do: :close
  defp guess_result(distance) when distance <= 4, do: :near
  defp guess_result(_distance), do: :far

  defp normalize(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/[^\w\s']/, "")
    |> String.replace(~r/\s+/, " ")
  end

  defp levenshtein(a, b) do
    a = String.graphemes(a)
    b = String.graphemes(b)

    Enum.reduce(a, Enum.to_list(0..length(b)), fn ca, previous ->
      {row, _left, _above_left} =
        Enum.reduce(
          Enum.with_index(b, 1),
          {[hd(previous) + 1], hd(previous) + 1, hd(previous)},
          fn {cb, index}, {row, left, above_left} ->
            above = Enum.at(previous, index)
            cost = if ca == cb, do: above_left, else: 1 + min(min(above, left), above_left)
            {[cost | row], cost, above}
          end
        )

      Enum.reverse(row)
    end)
    |> List.last()
  end

  defp call(room_id, message), do: GenServer.call(via(room_id), message)
  defp via(room_id), do: {:via, Registry, {LiveTrivia.GameRegistry, room_id}}
  defp topic(room_id), do: "#{@topic}:#{room_id}"

  defp room_id do
    case Registry.keys(LiveTrivia.GameRegistry, self()) do
      [room_id | _] -> room_id
      [] -> nil
    end
  end

  defp broadcast(state) do
    if room_id = room_id() do
      Phoenix.PubSub.broadcast(
        LiveTrivia.PubSub,
        topic(room_id),
        {:game_state, public_state(state)}
      )

      LiveTrivia.Lobby.room_state_changed(room_id, state.phase)
    end
  end

  defp touch_room do
    if room_id = room_id(), do: LiveTrivia.Lobby.touch_room(room_id)
  end

  defp now_ms, do: System.system_time(:millisecond)
end
