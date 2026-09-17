defmodule Pronotex.Pronote.EventTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote.Event

  test "recipient matching includes common events without matching another child's partial name" do
    child = %{"L" => "DUPONT Alice"}
    assert Event.for_child?(%{"listeEleves" => ["Alice"]}, child)
    assert Event.for_child?(%{"listeEleves" => ["Basile", "Alice"]}, child)
    assert Event.for_child?(%{"listeEleves" => []}, child)
    refute Event.for_child?(%{"listeEleves" => ["Basile"]}, child)
    refute Event.for_child?(%{"listeEleves" => ["Ed"]}, child)
  end
end
