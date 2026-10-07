defmodule Pronotex.Pronote.GradeTrend do
  @moduledoc "Chronological observations of official PRONOTE averages, expressed on a scale of 20."

  def points(snapshots, series \\ :overall) when series in [:overall, :class_overall] do
    snapshots
    |> Enum.sort_by(&{DateTime.to_unix(&1.observed_at, :microsecond), &1.id}, :desc)
    # Select the latest complete observation for each date shown on the chart.
    |> Enum.uniq_by(&DateTime.to_date(&1.observed_at))
    |> Enum.reverse()
    |> Enum.map(fn snapshot ->
      {snapshot.observed_at,
       %{overall: value(snapshot, :overall), class_overall: value(snapshot, :class_overall)}}
    end)
    # Keep both observations whenever either overall average changes.
    |> Enum.dedup_by(&elem(&1, 1))
    |> Enum.flat_map(fn {observed_at, values} ->
      case Map.fetch!(values, series) do
        nil -> []
        value -> [{observed_at, value}]
      end
    end)
  end

  defp value(snapshot, series) do
    score = number(snapshot.data[Atom.to_string(series)])
    scale = number(snapshot.data["overall_out_of"])

    if is_number(score) and is_number(scale) and scale > 0 and score >= 0 and score <= scale,
      do: score / scale * 20,
      else: nil
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
