defmodule Pronotex.Pronote.LessonContent do
  @moduledoc "Published lesson notes and their session-bound resources."
  alias Pronotex.Pronote.Crypto

  def parse(raw, transport) do
    html = get_in(raw, ["descriptif", "V"]) || ""
    tree = html |> Floki.parse_fragment!() |> Floki.filter_out("script, style")

    description =
      tree
      |> Floki.traverse_and_update(fn
        {tag, attrs, children} when tag in ["p", "div", "li", "br"] ->
          {tag, attrs, children ++ ["\n"]}

        node ->
          node
      end)
      |> Floki.text(sep: "")
      |> String.trim()

    links =
      for {"a", attrs, _} = node <- Floki.find(tree, "a[href]"),
          url = safe_url(List.keyfind(attrs, "href", 0) |> elem(1)),
          not is_nil(url),
          do: %{name: Floki.text([node]), url: url, type: :link}

    resources =
      (get_in(raw, ["ListePieceJointe", "V"]) || [])
      |> Enum.map(&resource(&1, transport))
      |> Enum.reject(&is_nil/1)

    %{
      title: raw["L"] || "",
      description: description,
      resources: Enum.uniq_by(resources ++ links, & &1.url)
    }
  end

  defp resource(%{"G" => 0} = raw, _) do
    if url = safe_url(raw["url"] || raw["L"]),
      do: %{name: raw["L"] || url, url: url, type: :link}
  end

  defp resource(%{"G" => 1, "N" => id, "L" => name}, transport) do
    token =
      Jason.encode!(%{"N" => id, "Actif" => true})
      |> Crypto.encrypt(transport.key, transport.iv)
      |> Crypto.hex()

    url =
      "#{transport.root}/FichiersExternes/#{token}/#{URI.encode(name, &URI.char_unreserved?/1)}?Session=#{transport.session}"

    %{name: name, url: url, type: :file}
  end

  defp resource(_, _), do: nil

  defp safe_url(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        value

      _ ->
        nil
    end
  end

  defp safe_url(_), do: nil
end
