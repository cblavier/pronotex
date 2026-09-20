defmodule Pronotex.Pronote.DiscussionTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote.Discussion

  test "placeholder IDs distinguish conversations and remain unchanged by read status" do
    first = %{"N" => "0", "listePossessionsMessages" => %{"V" => [%{"N" => "a"}]}}
    second = %{"N" => "0", "listePossessionsMessages" => %{"V" => [%{"N" => "b"}]}}
    refute Discussion.parse(first, []).id == Discussion.parse(second, []).id
    assert Discussion.id(first) == Discussion.id(Map.put(first, "lu", true))
  end
end
