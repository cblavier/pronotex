defmodule Pronotex.Pronote.Homework do
  @moduledoc "A homework assignment with a local due date and completion status."
  @derive Jason.Encoder
  defstruct [:id, :child_id, :subject, :color, :description, :date, done: false]

  @doc "Last date counted as urgent: tomorrow, or Monday when today is Saturday."
  def urgent_until(%Date{} = today) do
    Date.add(today, if(Date.day_of_week(today) == 6, do: 2, else: 1))
  end

  def parse(raw, child_id) do
    description =
      (get_in(raw, ["descriptif", "V"]) || "")
      |> Pronotex.Pronote.HTMLText.parse()

    %__MODULE__{
      id: Map.fetch!(raw, "N"),
      child_id: child_id,
      subject: get_in(raw, ["Matiere", "V", "L"]),
      color: Pronotex.Pronote.Color.parse(raw["CouleurFond"]),
      description: description,
      date: Pronotex.Pronote.Lesson.date(raw["PourLe"]["V"]),
      done: raw["TAFFait"] in [true, 1]
    }
  end
end
