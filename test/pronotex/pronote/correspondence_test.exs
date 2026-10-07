defmodule Pronotex.Pronote.CorrespondenceTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote.Correspondence

  test "multi-day absences retain dates, missed teaching time, reason and justification" do
    entry =
      Correspondence.parse(%{
        "N" => "absence",
        "G" => 13,
        "dateDebut" => %{"V" => "14/09/2026 08:10:00"},
        "dateFin" => %{"V" => "15/09/2026 17:50:00"},
        "NbrHeures" => "12h00",
        "justifie" => true,
        "listeMotifs" => %{"V" => [%{"L" => "Motif familial"}]}
      })

    assert entry.subject == "Absence aux cours"
    assert entry.date == "14/09/2026 08:10:00"

    assert hd(entry.messages).content ==
             "Du 14/09/2026 à 08h10 au 15/09/2026 à 17h50\n12h00 de cours manqués\nMotif : Motif familial"

    assert entry.unread == 0
  end

  test "resource types sharing the same number have distinct IDs and unknown types remain visible" do
    entries =
      for kind <- [13, 14, 21, 40, 41, 42, 46, 73, 999],
          do: Correspondence.parse(%{"N" => "same", "G" => kind})

    assert length(Enum.uniq_by(entries, & &1.id)) == length(entries)
    assert List.last(entries).subject == "Vie scolaire"
  end

  test "pending or missing justification is not presented as justified" do
    entry = %{"N" => "a", "G" => 13, "justifie" => false}
    assert Correspondence.parse(entry).justified == false
    refute hd(Correspondence.parse(entry).messages).content =~ "Absence non justifiée"

    assert hd(Correspondence.parse(Map.put(entry, "aRegulariser", true)).messages).content == ""

    assert hd(Correspondence.parse(Map.put(entry, "enAttente", true)).messages).content == ""

    assert hd(Correspondence.parse(Map.delete(entry, "justifie")).messages).content == ""
  end
end
