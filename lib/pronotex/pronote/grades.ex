defmodule Pronotex.Pronote.Grades do
  @moduledoc "Published marks and averages. Values remain strings; missing statistics are never recalculated."
  alias Pronotex.Pronote.Lesson

  def period_key(nil), do: nil

  def period_key(name) do
    name
    |> String.downcase()
    |> String.replace(~r/^semestre\s*(\d+)$/, "semester\\1")
    |> String.replace(~r/^trimestre\s*(\d+)$/, "trimester\\1")
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  def value(%{"V" => value}), do: value(value)
  def value(nil), do: nil
  def value(""), do: nil

  def value("|" <> code) do
    case String.first(code) do
      "1" -> "Absent"
      "2" -> "Dispensé"
      "3" -> "Non noté"
      "4" -> "Inapte"
      "5" -> "Non rendu"
      "6" -> "Absent (zéro)"
      "7" -> "Non rendu (zéro)"
      "8" -> "Félicitations"
      _ -> nil
    end
  end

  def value(value) when is_binary(value), do: value
  def value(value) when is_number(value), do: to_string(value)

  def parse(data) do
    grades =
      for raw <- get_in(data, ["listeDevoirs", "V"]) || [] do
        %{
          id: Map.fetch!(raw, "N"),
          subject: get_in(raw, ["service", "V", "L"]) || "Matière",
          date: Lesson.date(raw["date"]["V"]),
          score: value(raw["note"]),
          out_of: value(raw["bareme"]),
          average: value(raw["moyenne"]),
          min: value(raw["noteMin"]),
          max: value(raw["noteMax"]),
          coefficient: value(raw["coefficient"]),
          comment: raw["commentaire"],
          bonus: raw["estBonus"] in [true, 1],
          optional: raw["estFacultatif"] in [true, 1]
        }
      end

    averages =
      for raw <- get_in(data, ["listeServices", "V"]) || [] do
        %{
          id: Map.fetch!(raw, "N"),
          subject: raw["L"] || "Matière",
          score: value(raw["moyEleve"]),
          out_of: value(raw["baremeMoyEleve"]),
          average: value(raw["moyClasse"]),
          min: value(raw["moyMin"]),
          max: value(raw["moyMax"])
        }
      end

    %{
      grades: Enum.sort_by(grades, & &1.date, {:desc, Date}),
      averages: averages,
      overall: value(data["moyGenerale"]),
      class_overall: value(data["moyGeneraleClasse"]),
      overall_out_of: value(data["baremeMoyGenerale"])
    }
  end
end
