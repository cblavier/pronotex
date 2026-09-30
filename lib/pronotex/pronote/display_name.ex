defmodule Pronotex.Pronote.DisplayName do
  @moduledoc false

  def full(nil), do: ""

  def full(name) do
    words = name |> without_title() |> String.split()
    {surname, given} = Enum.split_while(words, &uppercase?/1)

    if surname != [] and given != [],
      do: Enum.join(given ++ Enum.map(surname, &titlecase/1), " "),
      else: Enum.join(words, " ")
  end

  def correspondent(name, sender) when is_binary(name) do
    head = name |> String.split(" - ", parts: 2) |> hd() |> without_title()
    raw = without_title(sender || "")
    {surname, given} = raw |> String.split() |> Enum.split_while(&uppercase?/1)
    initials = Enum.map(given, &(String.first(&1) <> "."))
    abbreviated = Enum.join(surname ++ initials, " ")

    if String.downcase(String.trim(name)) == "moi" or
         (raw != "" and head == raw) or
         (surname != [] and given != [] and head == abbreviated),
       do: full(sender),
       else: name
  end

  def recipients(resources, sender, account_resource) do
    resources
    |> Enum.filter(&is_binary(&1["L"]))
    |> Enum.map(fn resource ->
      name = correspondent(resource["L"], sender)

      own =
        if (is_map(account_resource) and account_resource["N"]) && resource["N"] do
          resource["N"] == account_resource["N"] and
            resource["G"] == account_resource["G"]
        else
          name != "" and name == full(sender)
        end

      {own, if(own, do: full(sender), else: name)}
    end)
    |> Enum.sort_by(fn {own, _} -> !own end)
    |> Enum.map(&elem(&1, 1))
  end

  defp without_title(name),
    do: name |> String.trim() |> String.replace(~r/^(?:M\.|Mme\.?|Mlle\.?)\s+/u, "")

  defp uppercase?(word), do: word == String.upcase(word) and word != String.downcase(word)

  defp titlecase(word) do
    word
    |> String.downcase()
    |> String.split(~r/([-’'])/u, include_captures: true)
    |> Enum.map_join(&String.capitalize/1)
  end
end
