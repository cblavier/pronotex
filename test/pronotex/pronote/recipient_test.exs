defmodule Pronotex.Pronote.RecipientTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote.Recipient

  test "teachers shared across child contexts merge their subjects without duplicates" do
    raw = %{
      "N" => "123",
      "G" => 3,
      "L" => "Mme Martin",
      "avecDiscussion" => true,
      "listeRessources" => %{"V" => [%{"G" => 16, "L" => "Mathématiques"}]}
    }

    other =
      put_in(raw, ["listeRessources", "V"], [
        %{"L" => "Mathématiques"},
        %{"L" => "Physique-chimie"}
      ])

    merged =
      Recipient.merge([
        Recipient.parse(raw),
        Recipient.parse(other),
        Recipient.parse(%{raw | "G" => 5}),
        Recipient.parse(%{raw | "avecDiscussion" => false})
      ])

    assert length(merged) == 2

    assert Enum.find(merged, &(&1.type == "Professeur")).subjects == [
             "Mathématiques",
             "Physique-chimie"
           ]

    assert Enum.find(merged, &(&1.type == "Responsable")).subjects == []
    refute Map.has_key?(hd(merged), :children)
  end

  test "missing subjects stay empty and unrelated resources are excluded" do
    raw = %{"N" => "123", "G" => 3, "L" => "Mme Martin", "avecDiscussion" => true}
    assert Recipient.parse(raw).subjects == []

    raw =
      Map.put(raw, "listeRessources", %{
        "V" => [
          %{"L" => "Mathématiques", "G" => 16},
          %{"L" => "Géométrie", "estUneSousMatiere" => true},
          %{"L" => "Alice", "G" => 4},
          %{"L" => " "},
          %{}
        ]
      })

    assert Recipient.parse(raw).subjects == ["Mathématiques"]
  end
end
