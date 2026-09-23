defmodule Pronotex.Pronote.DiscussionTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote.Discussion

  test "HTML messages use compact paragraphs while plain text keeps intentional spacing" do
    html = "<div><p>Bonjour<br></p></div>\n<p>&nbsp;</p><div><p>À demain</p></div>"
    plain = "Bonjour\n\nÀ demain"

    messages =
      Discussion.messages(%{
        "listeMessages" => %{
          "V" => [
            %{"N" => "html", "contenu" => html, "estHTML" => true},
            %{"N" => "plain", "contenu" => plain, "estHTML" => false}
          ]
        }
      })

    assert Enum.find(messages, &(&1.id == "html")).content == "Bonjour\nÀ demain"
    assert Enum.find(messages, &(&1.id == "plain")).content == plain
  end

  test "messages are chronological across months and preview uses the newest message" do
    raw =
      for {id, date} <- [
            {"newest", "02/10/2026 09:00:00"},
            {"middle", "30/09/2026 16:30:00"},
            {"oldest", "30/09/2026 08:00:00"}
          ],
          do: %{"N" => id, "date" => %{"V" => date}, "contenu" => id}

    messages = Discussion.messages(%{"listeMessages" => %{"V" => raw}})
    assert Enum.map(messages, & &1.id) == ["oldest", "middle", "newest"]
    assert Discussion.parse(%{"N" => "thread"}, messages).preview == "newest"
  end

  test "placeholder IDs distinguish conversations and remain unchanged by read status" do
    first = %{"N" => "0", "listePossessionsMessages" => %{"V" => [%{"N" => "a"}]}}
    second = %{"N" => "0", "listePossessionsMessages" => %{"V" => [%{"N" => "b"}]}}
    refute Discussion.parse(first, []).id == Discussion.parse(second, []).id
    assert Discussion.id(first) == Discussion.id(Map.put(first, "lu", true))
  end
end
