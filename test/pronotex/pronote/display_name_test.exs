defmodule Pronotex.Pronote.DisplayNameTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote.DisplayName

  test "the account recipient comes first even with a different label and a later position" do
    account = %{"N" => "parent", "G" => 2}

    recipients = [
      %{"N" => "other", "G" => 2, "L" => "Autre parent"},
      %{"N" => "teacher", "G" => 3, "L" => "Mme Martin"},
      %{"N" => "parent", "G" => 2, "L" => "BLAVIER C. (responsable)"}
    ]

    assert DisplayName.recipients(recipients, "M. BLAVIER Christian", account) ==
             ["Christian Blavier", "Autre parent", "Mme Martin"]
  end

  test "name matching also prioritizes the account when resource IDs are unavailable" do
    recipients = [%{"L" => "Mme Martin"}, %{"L" => "Moi"}, %{"L" => "M. Dupont"}]

    assert DisplayName.recipients(recipients, "M. BLAVIER Christian", nil) ==
             ["Christian Blavier", "Mme Martin", "M. Dupont"]
  end

  test "formats the full account name without changing already formatted names" do
    assert DisplayName.full("M. BLAVIER Christian") == "Christian Blavier"
    assert DisplayName.full("Christian Blavier") == "Christian Blavier"
    assert DisplayName.full("Mme DUPONT-MARTIN Anne") == "Anne Dupont-Martin"
  end

  test "recognizes the account's abbreviated recipient label with children" do
    sender = "M. BLAVIER Christian"
    assert DisplayName.correspondent("Moi", sender) == "Christian Blavier"
    assert DisplayName.correspondent(sender, sender) == "Christian Blavier"

    assert DisplayName.correspondent(
             "M. BLAVIER C. - BLAVIER Alice (5B) BLAVIER Marius (3A)",
             sender
           ) == "Christian Blavier"

    assert DisplayName.correspondent("M. BLAVIER J. - BLAVIER Alice (5B)", sender) ==
             "M. BLAVIER J. - BLAVIER Alice (5B)"

    assert DisplayName.correspondent("Mme MARTIN E.", sender) == "Mme MARTIN E."
  end
end
