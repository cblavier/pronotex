defmodule PronotexWeb.MessageComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias PronotexWeb.MessageComponents

  test "sent messages show recipients instead of the current user" do
    html =
      render_component(&MessageComponents.message_correspondents/1,
        message: %{own: true, author: "Moi", recipients: ["Mme Martin", "M. Dupont"]}
      )

    assert html =~ "À :"
    assert html =~ ~s(data-direction="sent")
    assert html =~ "Mme Martin, M. Dupont"
    refute html =~ "Moi"
  end

  test "conversation messages show sender then recipients on separate lines" do
    for own <- [true, false] do
      html =
        render_component(&MessageComponents.message_correspondents/1,
          message: %{own: own, author: "Camille", recipients: ["Mme Martin", "M. Dupont"]},
          details: true
        )

      lines = html |> Floki.parse_fragment!() |> Floki.find(".message-correspondent-line")
      assert length(lines) == 2
      assert Floki.text(Enum.at(lines, 0)) =~ "De :"
      assert Floki.text(Enum.at(lines, 0)) =~ "Camille"
      assert Floki.text(Enum.at(lines, 1)) =~ "À :"
      assert Floki.text(Enum.at(lines, 1)) =~ "Mme Martin, M. Dupont"
    end
  end

  test "more than two recipients collapse to one name and an exact remaining count" do
    recipients = ["Christian Blavier" | Enum.map(1..25, &"Destinataire #{&1}")]

    html =
      render_component(&MessageComponents.message_correspondents/1,
        id: "correspondents-example",
        details: true,
        message: %{author: "Mme Martin", recipients: recipients}
      )

    tree = Floki.parse_fragment!(html)
    assert tree |> Floki.find(".message-recipients-count") |> Floki.text() == "+25"
    toggle = Floki.find(tree, "a.message-recipients-toggle")
    assert Floki.attribute(toggle, "aria-expanded") == ["false"]
    assert Floki.attribute(toggle, "aria-controls") == ["correspondents-example-all"]
    all = Floki.find(tree, "#correspondents-example-all")
    assert Floki.attribute(all, "style") == ["display: none;"]
    assert Floki.text(all) =~ Enum.join(recipients, ", ")
  end

  test "two recipients remain fully visible without a toggle" do
    html =
      render_component(&MessageComponents.message_correspondents/1,
        details: true,
        message: %{author: "Mme Martin", recipients: ["Christian Blavier", "Mme Dupont"]}
      )

    assert html =~ "Christian Blavier, Mme Dupont"
    refute html =~ "message-recipients-toggle"
  end

  test "received messages and notices show their author" do
    for message <- [%{own: false, author: "Mme Martin"}, %{author: "Vie scolaire"}] do
      html = render_component(&MessageComponents.message_correspondents/1, message: message)
      assert html =~ "De :"
      assert html =~ ~s(data-direction="received")
      assert html =~ message.author
    end
  end
end
