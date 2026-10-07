defmodule PronotexWeb.HeroiconsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  test "each icon style includes its paths in the HTML without a CSS image mask" do
    for name <-
          ~w(hero-calendar-days hero-academic-cap-solid hero-pencil-square-mini hero-cog-6-tooth-micro) do
      html = render_component(&PronotexWeb.CoreComponents.icon/1, name: name, class: "size-6")
      document = Floki.parse_fragment!(html)
      assert [_] = Floki.find(document, "svg.size-6")
      assert Floki.find(document, "svg path") != []
      assert Floki.find(document, "span, image") == []
      refute html =~ "data:image"
      refute html =~ ~s(class="#{name})
    end
  end
end
