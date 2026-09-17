defmodule Pronotex.Pronote.Lesson do
  @moduledoc "A timetable entry. Times are local school times (Europe/Paris), not UTC."
  @derive Jason.Encoder
  defstruct [
    :id,
    :subject,
    :start,
    :end,
    :status,
    :memo,
    :child_id,
    teachers: [],
    classrooms: [],
    groups: [],
    canceled: false,
    priority: 0
  ]

  def parse(raw, general, child_id) do
    start = datetime(raw["DateDuCours"]["V"])

    ending =
      case get_in(raw, ["DateDuCoursFin", "V"]) do
        nil -> grid_end(raw, general, start)
        value -> datetime(value)
      end

    contents = raw["ListeContenus"]["V"]

    %__MODULE__{
      id: Map.fetch!(raw, "N"),
      child_id: child_id,
      subject: contents |> labels(16) |> List.first(),
      teachers: labels(contents, 3),
      classrooms: labels(contents, 17),
      groups: labels(contents, 2),
      start: start,
      end: ending,
      canceled: raw["estAnnule"] || false,
      priority: raw["P"] || 0,
      status: raw["Statut"],
      memo: raw["memo"]
    }
  end

  def date(value), do: value |> datetime() |> NaiveDateTime.to_date()

  def datetime(value) do
    case Regex.run(
           ~r/^(\d{2})\/(\d{2})\/(\d{4}|\d{2})(?: (\d{2})[:h](\d{2})(?::(\d{2}))?)?$/,
           value,
           capture: :all_but_first
         ) do
      [day, month, year | clock] ->
        year = String.to_integer(year)
        year = if year < 100, do: year + 2000, else: year
        [hour, minute, second] = Enum.take(clock ++ ["", "", ""], 3)
        date = Date.new!(year, String.to_integer(month), String.to_integer(day))
        time = Time.new!(integer(hour), integer(minute), integer(second))
        NaiveDateTime.new!(date, time)

      _ ->
        raise Pronotex.Pronote.Error.new(:protocol)
    end
  end

  defp labels(contents, genre) do
    for %{"G" => ^genre, "L" => label} <- contents, do: label
  end

  defp grid_end(raw, general, start) do
    times = general["ListeHeuresFin"]["V"]
    slots = length(times) - 1
    position = rem(raw["place"], slots) + raw["duree"] - 1
    position = if position > length(times), do: rem(position, slots), else: position
    %{"L" => label} = Enum.find(times, &(&1["G"] == position))
    [hour, minute] = String.split(label, "h")
    NaiveDateTime.new!(NaiveDateTime.to_date(start), Time.new!(integer(hour), integer(minute), 0))
  end

  defp integer(""), do: 0
  defp integer(value), do: String.to_integer(value)
end
