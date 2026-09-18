defmodule Pronotex.Pronote.Event do
  @moduledoc "Read-only school agenda event, distinct from a timetable lesson."
  alias Pronotex.Pronote.Lesson
  defstruct [:id, :title, :description, :start, :end]

  def imminent?(event, today) do
    next_workday =
      Date.add(
        today,
        case Date.day_of_week(today) do
          5 -> 3
          6 -> 2
          _ -> 1
        end
      )

    first = NaiveDateTime.to_date(event.start)
    last = NaiveDateTime.to_date(event.end || event.start)

    Enum.any?([today, next_workday], fn date ->
      Date.compare(first, date) != :gt and Date.compare(last, date) != :lt
    end)
  end

  def parse(raw) do
    %__MODULE__{
      id: Map.fetch!(raw, "N"),
      title: String.trim(raw["L"] || "Événement"),
      description: raw["Commentaire"] || "",
      start: Lesson.datetime(raw["DateDebut"]["V"]),
      end: Lesson.datetime(raw["DateFin"]["V"])
    }
  end

  def for_child?(raw, child) do
    names = raw["listeEleves"] || []
    full = normalize(child["L"] || "")
    words = String.split(child["L"] || "")
    given = Enum.drop_while(words, &(&1 == String.upcase(&1)))

    given =
      case given do
        [] -> List.last(words) || ""
        ^words -> List.first(words) || ""
        names -> Enum.join(names, " ")
      end

    aliases = Enum.map([full, child["prenom"] || given], &normalize/1)
    names == [] or Enum.any?(names, &(normalize(&1) in aliases))
  end

  defp normalize(name),
    do: name |> String.trim() |> String.downcase() |> String.replace(~r/\s+/u, " ")
end
