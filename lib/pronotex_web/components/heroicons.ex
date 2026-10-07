defmodule PronotexWeb.Heroicons do
  @moduledoc false

  @icons (for {suffix, directory} <- [
                {"", "24/outline"},
                {"-solid", "24/solid"},
                {"-mini", "20/solid"},
                {"-micro", "16/solid"}
              ],
              path <- Path.wildcard(Path.join(["deps/heroicons/optimized", directory, "*.svg"])),
              into: %{} do
            @external_resource path
            [{"svg", attributes, children}] = path |> File.read!() |> Floki.parse_fragment!()
            name = "hero-" <> Path.basename(path, ".svg") <> suffix
            {name, {attributes, Phoenix.HTML.raw(Floki.raw_html(children))}}
          end)

  def fetch!(name), do: Map.fetch!(@icons, name)
end
