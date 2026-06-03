defmodule LiveTriviaWeb.ResultColors do
  @moduledoc false

  def result_color(:correct, _fallback), do: "#22c55e"
  def result_color(:close, _fallback), do: "#eab308"
  def result_color(:near, _fallback), do: "#f97316"
  def result_color(:far, _fallback), do: "#ef4444"
  def result_color(_result, fallback), do: fallback
end
