defmodule Pronotex.Pronote.EventTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote.Event

  test "highlights today or the next weekday, including events spanning several days" do
    friday = ~D[2026-09-18]

    event = fn from, to ->
      %Event{
        start: NaiveDateTime.new!(from, ~T[09:00:00]),
        end: NaiveDateTime.new!(to, ~T[17:00:00])
      }
    end

    assert Event.imminent?(event.(friday, friday), friday)
    assert Event.imminent?(event.(~D[2026-09-21], ~D[2026-09-21]), friday)
    assert Event.imminent?(event.(~D[2026-09-17], ~D[2026-09-22]), friday)
    refute Event.imminent?(event.(~D[2026-09-19], ~D[2026-09-20]), friday)
    refute Event.imminent?(event.(~D[2026-09-22], ~D[2026-09-22]), friday)
    refute Event.imminent?(event.(~D[2026-09-17], ~D[2026-09-17]), friday)

    for today <- [~D[2026-09-19], ~D[2026-09-20]] do
      assert Event.imminent?(event.(~D[2026-09-21], ~D[2026-09-21]), today)
    end

    assert Event.imminent?(event.(~D[2026-09-22], ~D[2026-09-22]), ~D[2026-09-21])
  end

  test "recipient matching includes common events without matching another child's partial name" do
    child = %{"L" => "DUPONT Alice"}
    assert Event.for_child?(%{"listeEleves" => ["Alice"]}, child)
    assert Event.for_child?(%{"listeEleves" => ["Basile", "Alice"]}, child)
    assert Event.for_child?(%{"listeEleves" => []}, child)
    refute Event.for_child?(%{"listeEleves" => ["Basile"]}, child)
    refute Event.for_child?(%{"listeEleves" => ["Ed"]}, child)
  end
end
