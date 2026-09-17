defmodule Pronotex.Pronote.Homework do
  @moduledoc "A homework assignment with a local due date and completion status."
  @derive Jason.Encoder
  defstruct [:id, :child_id, :subject, :description, :date, done: false]

  def parse(raw, child_id) do
    description =
      (get_in(raw, ["descriptif", "V"]) || "")
      |> Floki.parse_fragment!()
      |> Floki.filter_out("script, style")
      |> Floki.traverse_and_update(fn
        {tag, attrs, children} when tag in ["p", "div", "li", "br"] ->
          {tag, attrs, children ++ ["\n"]}

        node ->
          node
      end)
      |> Floki.text(sep: "")
      |> String.trim()

    %__MODULE__{
      id: Map.fetch!(raw, "N"),
      child_id: child_id,
      subject: get_in(raw, ["Matiere", "V", "L"]),
      description: description,
      date: Pronotex.Pronote.Lesson.date(raw["PourLe"]["V"]),
      done: raw["TAFFait"] in [true, 1]
    }
  end
end
