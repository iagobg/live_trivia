defmodule LiveTrivia.PlayerColors do
  @colors [
    "#E11D48",
    "#2563EB",
    "#CA8A04",
    "#059669",
    "#7C3AED",
    "#0891B2",
    "#EA580C",
    "#DB2777",
    "#65A30D",
    "#9333EA",
    "#0F766E",
    "#B45309",
    "#4F46E5",
    "#BE123C",
    "#0284C7",
    "#15803D"
  ]

  def all, do: @colors

  def valid?(color), do: color in @colors
end
