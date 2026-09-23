defmodule Pronotex.Pronote.GradeTrend do
  @moduledoc "Chronological observations of official PRONOTE averages, expressed on a scale of 20."

  def points(snapshots) do
    snapshots
    |> Enum.sort_by(&{DateTime.to_unix(&1.observed_at, :microsecond), &1.id})
    |> Enum.flat_map(fn snapshot ->
      score = number(snapshot.data["overall"])
      scale = number(snapshot.data["overall_out_of"])

      if is_number(score) and is_number(scale) and scale > 0 and score >= 0 and score <= scale,
        do: [{snapshot.observed_at, score / scale * 20}],
        else: []
    end)
    # Class/subject statistics can change without changing the overall average.
    |> Enum.dedup_by(&elem(&1, 1))
  end

  defp number(value) when is_binary(value) do
    case Float.parse(String.replace(String.trim(value), ",", ".")) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp number(value) when is_number(value), do: value
  defp number(_), do: nil
end
