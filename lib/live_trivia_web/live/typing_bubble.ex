defmodule LiveTriviaWeb.TypingBubble do
  use LiveTriviaWeb, :html

  attr :id, :string, required: true
  attr :player, :map, required: true
  attr :text, :string, required: true
  attr :submitted, :boolean, default: false
  attr :class, :any, default: nil

  def typing_bubble(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="TypingBubble"
      class={[
        "typing-bubble translate-y-0 overflow-hidden border font-semibold text-white opacity-100 shadow-lg",
        if(@submitted, do: "is-submitted", else: "is-live"),
        @submitted && animation_enabled?() && "is-animated",
        @class
      ]}
      phx-remove={
        JS.transition(
          {"transition ease-out duration-500", "opacity-100 translate-y-0",
           "opacity-0 -translate-y-4"},
          time: 500
        )
      }
      style={typing_bubble_style(@player)}
    >
      <span class="typing-bubble-content">{@text}</span>
    </div>
    """
  end

  def typing_entry(text), do: %{text: text}

  def submitted_entry(id, text), do: %{id: id, text: text}

  def text(%{text: text}), do: text
  def text(text) when is_binary(text), do: text
  def text(_entry), do: ""

  def active_text(%{typing: typing}), do: text(typing)
  def active_text(entry), do: text(entry)

  def submitted_bubbles(%{submitted: submitted}) when is_list(submitted), do: submitted
  def submitted_bubbles(_entry), do: []

  def visible_count(entry) do
    active =
      if active_text(entry) == "" do
        0
      else
        1
      end

    active + length(submitted_bubbles(entry))
  end

  def submitted_count(entry), do: length(submitted_bubbles(entry))

  def animation_enabled? do
    Application.get_env(:live_trivia, :typing_bubble_animation?, true)
  end

  def update_player_bubbles(typing_by_player, player_id, :typing, text, _bubble_id) do
    Map.update(
      typing_by_player,
      player_id,
      put_typing(nil, text),
      &put_typing(&1, text)
    )
  end

  def update_player_bubbles(typing_by_player, player_id, :submitted, text, bubble_id) do
    Map.update(
      typing_by_player,
      player_id,
      add_submitted(nil, bubble_id, text),
      &add_submitted(&1, bubble_id, text)
    )
  end

  def update_player_bubbles(typing_by_player, player_id, :remove_submitted, _text, bubble_id) do
    Map.update(
      typing_by_player,
      player_id,
      remove_submitted(nil, bubble_id),
      &remove_submitted(&1, bubble_id)
    )
  end

  def update_player_bubbles(typing_by_player, player_id, _mode, text, _bubble_id) do
    update_player_bubbles(typing_by_player, player_id, :typing, text, nil)
  end

  def put_typing(entry, text) do
    entry
    |> normalize_entry()
    |> Map.put(:typing, typing_entry(text))
  end

  def add_submitted(entry, id, text) do
    entry = normalize_entry(entry)
    submitted = submitted_bubbles(entry)

    cond do
      !animation_enabled?() ->
        entry
        |> Map.put(:typing, typing_entry(""))
        |> Map.put(:submitted, [])

      Enum.any?(submitted, &(&1.id == id)) ->
        entry

      true ->
        entry
        |> Map.put(:typing, typing_entry(""))
        |> Map.put(:submitted, submitted ++ [submitted_entry(id, text)])
    end
  end

  def remove_submitted(entry, id) do
    entry = normalize_entry(entry)

    Map.put(
      entry,
      :submitted,
      Enum.reject(submitted_bubbles(entry), &(&1.id == id))
    )
  end

  defp normalize_entry(%{typing: _typing} = entry), do: Map.put_new(entry, :submitted, [])

  defp normalize_entry(%{submitted: _submitted} = entry),
    do: Map.put_new(entry, :typing, typing_entry(""))

  defp normalize_entry(text) when is_binary(text),
    do: %{typing: typing_entry(text), submitted: []}

  defp normalize_entry(_entry), do: %{typing: typing_entry(""), submitted: []}

  defp typing_bubble_style(player) do
    "border-color: #{player.color}aa; background-color: #{player.color}dd; box-shadow: 0 0 18px #{player.color}66;"
  end
end
