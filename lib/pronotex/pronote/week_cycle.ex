defmodule Pronotex.Pronote.WeekCycle do
  @moduledoc false

  alias Pronotex.Pronote.Lesson

  def calendar(general) do
    with %{"V" => first} <- general["PremierLundi"],
         domains when is_list(domains) <- general["DomainesFrequences"] do
      monday = Lesson.date(first)

      for {fallback, index} <- [{"A", 1}, {"B", 2}],
          week <- weeks(Enum.at(domains, index)),
          into: %{},
          do: {Date.add(monday, (week - 1) * 7), cycle_label(general, index, fallback)}
    else
      _ -> %{}
    end
  end

  def counterpart(calendar, monday) do
    case calendar[monday] do
      nil ->
        nil

      cycle ->
        calendar
        |> Enum.filter(fn {_, other} -> other != cycle end)
        |> Enum.min_by(
          fn {date, _} -> {abs(Date.diff(date, monday)), Date.compare(date, monday) == :lt} end,
          fn -> nil end
        )
    end
  end

  def overlay(current, other, monday, other_monday, cycle) do
    keys = MapSet.new(current, &slot/1)
    shift = Date.diff(monday, other_monday) * 86_400

    inactive =
      other
      |> Enum.reject(&(&1.canceled or MapSet.member?(keys, slot(&1))))
      |> Enum.uniq_by(&slot/1)
      |> Enum.map(fn lesson ->
        lesson
        |> Map.put(:start, NaiveDateTime.add(lesson.start, shift))
        |> Map.put(:end, NaiveDateTime.add(lesson.end, shift))
        |> Map.put(:inactive_cycle, cycle)
        |> Map.put(:reference_date, NaiveDateTime.to_date(lesson.start))
      end)

    current ++ inactive
  end

  defp slot(lesson) do
    {lesson.subject, Date.day_of_week(NaiveDateTime.to_date(lesson.start)),
     NaiveDateTime.to_time(lesson.start), NaiveDateTime.to_time(lesson.end)}
  end

  defp cycle_label(general, index, fallback) do
    label = Enum.at(general["LibellesFrequences"] || [], index)

    case is_binary(label) && Regex.run(~r/\b([AB])\b/i, label) do
      [_, cycle] -> String.upcase(cycle)
      _ -> fallback
    end
  end

  defp weeks(%{"V" => value}) when is_binary(value) do
    value
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.split(",", trim: true)
    |> Enum.flat_map(fn part ->
      case String.split(String.trim(part), "..") do
        [first, last] ->
          with {a, ""} <- Integer.parse(first),
               {b, ""} <- Integer.parse(last),
               true <- a <= b,
               do: Enum.to_list(a..b),
               else: (_ -> [])

        [single] ->
          case Integer.parse(single) do
            {n, ""} -> [n]
            _ -> []
          end

        _ ->
          []
      end
    end)
  end

  defp weeks(_), do: []
end
