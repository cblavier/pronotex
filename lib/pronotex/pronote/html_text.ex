defmodule Pronotex.Pronote.HTMLText do
  @moduledoc "Converts Pronote HTML to plain text. Messages retain intentional blank lines."

  def parse(html) do
    html
    |> Floki.parse_fragment!()
    |> Floki.filter_out("script, style")
    |> message_text()
    |> String.replace(~r/[^\S\n]+\n/u, "\n")
    |> String.trim()
  end

  defp message_text(nodes) do
    Enum.reduce(nodes, "", fn
      {"br", _, _}, text ->
        text <> "\n"

      {tag, _, children}, text when tag in ["p", "div", "li"] ->
        content = message_text(children)

        separator =
          if text == "" or String.ends_with?(String.trim_trailing(text, " "), "\n"),
            do: "",
            else: "\n"

        ending = if String.ends_with?(content, "\n"), do: "", else: "\n"
        String.trim_trailing(text, " ") <> separator <> content <> ending

      {_, _, children}, text ->
        text <> message_text(children)

      value, text when is_binary(value) ->
        value = String.replace(value, ~r/[\s\x{00A0}]+/u, " ")

        if value == " " and (text == "" or String.ends_with?(text, "\n")),
          do: text,
          else: text <> value

      _, text ->
        text
    end)
  end

  def from_tree(tree) do
    tree
    |> Floki.filter_out("script, style")
    |> Floki.traverse_and_update(fn
      {tag, attrs, children} when tag in ["p", "div", "li", "br"] ->
        {tag, attrs, children ++ ["\n"]}

      node ->
        node
    end)
    |> Floki.text(sep: "")
    |> String.replace(~r/\r\n?/, "\n")
    |> String.replace(~r/[^\S\n]*\n[\s\x{00A0}]*/u, "\n")
    |> String.trim()
  end
end
