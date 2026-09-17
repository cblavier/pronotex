defmodule Pronotex.Pronote.Menu do
  @moduledoc "A published canteen meal, read without modifying school data."
  defstruct [:id, :date, :name, :kind, courses: []]

  def parse(raw, date) do
    labels = %{
      0 => "Entrées",
      1 => "Plats",
      2 => "Accompagnements",
      3 => "Autres",
      4 => "Desserts",
      5 => "Fromages"
    }

    courses =
      for course <- get_in(raw, ["ListePlats", "V"]) || [],
          foods = Enum.map(get_in(course, ["ListeAliments", "V"]) || [], &Map.fetch!(&1, "L")),
          foods != [] do
        %{label: Map.get(labels, course["G"], "Autres"), foods: foods}
      end

    %__MODULE__{
      id: raw["N"],
      name: raw["L"],
      date: Pronotex.Pronote.Lesson.date(date),
      kind: if(raw["G"] == 1, do: "Dîner", else: "Déjeuner"),
      courses: courses
    }
  end
end
