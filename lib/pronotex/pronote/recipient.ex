defmodule Pronotex.Pronote.Recipient do
  @moduledoc false

  def parse(raw) do
    if raw["avecDiscussion"] == true and raw["G"] in [3, 5, 34] and
         is_binary(raw["N"]) and is_binary(raw["L"]) do
      %{
        id: "#{raw["G"]}:#{raw["N"]}",
        name: raw["L"],
        type: %{3 => "Professeur", 5 => "Responsable", 34 => "Personnel"}[raw["G"]],
        subjects: subjects(raw),
        resource: Map.take(raw, ["N", "G", "L"])
      }
    end
  end

  def merge(recipients) do
    recipients
    |> Enum.reject(&is_nil/1)
    |> Enum.group_by(& &1.id)
    |> Enum.map(fn {_, [first | _] = entries} ->
      %{first | subjects: entries |> Enum.flat_map(& &1.subjects) |> Enum.uniq()}
    end)
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  defp subjects(%{"G" => 3} = raw) do
    (get_in(raw, ["listeRessources", "V"]) || [])
    |> Enum.filter(&(is_map(&1) and &1["G"] in [nil, 16] and &1["estUneSousMatiere"] != true))
    |> Enum.map(& &1["L"])
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp subjects(_), do: []

  def valid_message?(ids, subject, content) do
    is_list(ids) and ids != [] and length(ids) <= 100 and Enum.all?(ids, &is_binary/1) and
      is_binary(subject) and String.trim(subject) != "" and String.length(subject) <= 200 and
      valid_content?(content)
  end

  def valid_content?(content),
    do: is_binary(content) and String.trim(content) != "" and String.length(content) <= 20_000
end
