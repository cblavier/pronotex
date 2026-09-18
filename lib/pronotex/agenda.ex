defmodule Pronotex.Agenda do
  @moduledoc "Presentation of a day's lessons, replacements and gaps."

  def entries(lessons) do
    active = Enum.reject(lessons, & &1.canceled)

    lessons
    |> Enum.reject(fn lesson ->
      lesson.canceled and Enum.any?(active, &overlap?(lesson, &1))
    end)
    |> Enum.sort_by(& &1.start, NaiveDateTime)
    |> Enum.map_reduce(nil, fn lesson, previous_end ->
      pause =
        if previous_end && NaiveDateTime.compare(previous_end, lesson.start) == :lt do
          %{start: previous_end, end: lesson.start}
        end

      ending =
        if previous_end && NaiveDateTime.compare(previous_end, lesson.end) == :gt,
          do: previous_end,
          else: lesson.end

      {Map.put(lesson, :pauses_before, split_pause(pause, lesson.lunch_window)), ending}
    end)
    |> elem(0)
  end

  defp split_pause(nil, _), do: []
  defp split_pause(pause, nil), do: [Map.put(pause, :label, "Pause")]

  defp split_pause(pause, lunch) do
    [pause.start, pause.end, lunch.start, lunch.end]
    |> Enum.filter(fn time ->
      NaiveDateTime.compare(time, pause.start) != :lt and
        NaiveDateTime.compare(time, pause.end) != :gt
    end)
    |> Enum.uniq()
    |> Enum.sort(NaiveDateTime)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [from, to] ->
      label =
        if NaiveDateTime.compare(from, lunch.start) != :lt and
             NaiveDateTime.compare(to, lunch.end) != :gt,
           do: "Repas",
           else: "Pause"

      %{start: from, end: to, label: label}
    end)
  end

  defp overlap?(left, right) do
    NaiveDateTime.compare(left.start, right.end) == :lt and
      NaiveDateTime.compare(right.start, left.end) == :lt
  end
end
