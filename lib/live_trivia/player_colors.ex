defmodule LiveTrivia.PlayerColors do
  @colors [
    "#60a5fa",
    "#34d399",
    "#f87171",
    "#fbbf24",
    "#a78bfa",
    "#fb7185",
    "#22d3ee",
    "#f97316",
    "#84cc16",
    "#e879f9",
    "#38bdf8",
    "#fde047",
    "#c084fc",
    "#4ade80",
    "#f472b6",
    "#2dd4bf"
  ]

  def all, do: @colors

  def valid?(color), do: color in @colors
end
