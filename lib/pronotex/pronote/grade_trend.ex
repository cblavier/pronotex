defmodule Pronotex.Pronote.GradeTrend do
  @moduledoc "Estimated cumulative trend, using equally weighted subjects and weighted marks."

  def points(grades) do
    grades
    |> Enum.reject(&(&1.bonus || &1.optional))
    |> Enum.flat_map(fn grade ->
      score =
        if grade.score in ["Absent (zéro)", "Non rendu (zéro)"],
          do: 0.0,
          else: number(grade.score)

      out_of = number(grade.out_of)
      coefficient = if is_nil(grade.coefficient), do: 1.0, else: number(grade.coefficient)

      if is_number(score) and is_number(out_of) and out_of > 0 and
           is_number(coefficient) and coefficient > 0 and score >= 0 and score <= out_of do
        [{grade.date, grade.subject, score / out_of * 20, coefficient}]
      else
        []
      end
    end)
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.sort_by(&elem(&1, 0), Date)
    |> Enum.map_reduce(%{}, fn {date, marks}, subjects ->
      subjects =
        Enum.reduce(marks, subjects, fn {_, subject, score, coefficient}, acc ->
          Map.update(acc, subject, {score * coefficient, coefficient}, fn {sum, weight} ->
            {sum + score * coefficient, weight + coefficient}
          end)
        end)

      average =
        Enum.sum(for {_, {sum, weight}} <- subjects, do: sum / weight) / map_size(subjects)

      {{date, average}, subjects}
    end)
    |> elem(0)
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
