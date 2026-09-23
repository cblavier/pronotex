defmodule Pronotex.Pronote.HTMLText do
  @moduledoc "Converts Pronote HTML into compact plain text with paragraph breaks."

  def parse(html) do
    html
    |> Floki.parse_fragment!()
    |> from_tree()
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
