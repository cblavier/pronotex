defmodule Pronotex.Pronote.Discussion do
  @moduledoc "Student discussions, rendered as plain text; reading never marks them as seen."

  def messages(data) do
    messages =
      for raw <- get_in(data, ["listeMessages", "V"]) || [] do
        content = raw["contenu"]
        content = if is_map(content), do: content["V"], else: content

        %{
          id: raw["N"],
          author: if(raw["emetteur"] == true, do: "Moi", else: raw["public_gauche"] || ""),
          own: raw["emetteur"] == true,
          seen: Map.get(raw, "lu", true) == true,
          date: get_in(raw, ["date", "V"]) || "",
          content: if(raw["estHTML"] == true, do: plain_text(content || ""), else: content || "")
        }
      end

    Enum.sort_by(messages, &message_time/1)
  end

  defp message_time(message) do
    message.date
    |> Pronotex.Pronote.Lesson.datetime()
    |> NaiveDateTime.diff(~N[0000-01-01 00:00:00], :second)
  rescue
    _ in [Pronotex.Pronote.Error, ArgumentError] -> 0
  end

  # PRONOTE can return the placeholder N=0 for multiple discussion roots.
  # Message possession references distinguish them without using their mutable read status.
  def id(raw) do
    case raw["N"] do
      value when value not in [nil, 0, "0", ""] ->
        to_string(value)

      _ ->
        references =
          (get_in(raw, ["listePossessionsMessages", "V"]) || [])
          |> Enum.map(&Map.take(&1, ["N", "G"]))
          |> Enum.sort()

        :crypto.hash(:sha256, :erlang.term_to_binary(references))
        |> Base.url_encode64(padding: false)
    end
  end

  def parse(raw, messages) do
    %{
      id: id(raw),
      kind: :discussion,
      subject: if(raw["objet"] in [nil, ""], do: "Sans objet", else: raw["objet"]),
      author: raw["initiateur"] || "",
      date: messages |> List.last(%{date: raw["libelleDate"] || ""}) |> Map.fetch!(:date),
      unread:
        Map.get(
          raw,
          "nbNonLus",
          if(raw["lu"] == false,
            do: max(Enum.count(messages, &(!&1.seen && !&1.own)), 1),
            else: 0
          )
        ),
      messages: messages,
      preview:
        messages |> List.last(%{content: ""}) |> Map.fetch!(:content) |> String.slice(0, 160)
    }
  end

  defp plain_text(text) do
    text
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
  end
end
