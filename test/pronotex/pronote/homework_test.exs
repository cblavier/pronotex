defmodule Pronotex.Pronote.HomeworkTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote.Homework

  test "homework paragraphs do not accumulate blank lines from nested HTML blocks" do
    raw = %{
      "N" => "task",
      "PourLe" => %{"V" => "18/09/2026"},
      "descriptif" => %{
        "V" => """
        <div><p>Revoir la <strong>leçon</strong>.<br></p></div>
        <p>&nbsp;</p>
        <div><p>Finir les ex 8 et 36.</p></div>
        <div><p>Faire l'ex 37</p></div>
        """
      }
    }

    assert Homework.parse(raw, "child").description ==
             "Revoir la leçon.\nFinir les ex 8 et 36.\nFaire l'ex 37"
  end

  test "homework keeps line breaks and removes hidden HTML content" do
    raw = %{
      "N" => "task",
      "PourLe" => %{"V" => "18/09/2026"},
      "descriptif" => %{
        "V" =>
          "<style>hidden</style><script>hidden</script>Lire<br>Apprendre<br><ul><li>Un</li><li>Deux</li></ul>"
      }
    }

    assert Homework.parse(raw, "child").description == "Lire\nApprendre\nUn\nDeux"
  end

  test "homework uses its API color and keeps missing or invalid colors neutral" do
    raw = %{
      "N" => "task",
      "Matiere" => %{"V" => %{"L" => "Nouvelle matière"}},
      "PourLe" => %{"V" => "18/09/2026"}
    }

    assert Homework.parse(raw, "child").color == nil
    assert Homework.parse(Map.put(raw, "CouleurFond", "#D4534C"), "child").color == "#D4534C"

    for invalid <- ["", "red", "#D4534C;display:none", 123] do
      assert Homework.parse(Map.put(raw, "CouleurFond", invalid), "child").color == nil
    end
  end

  test "homework includes signed files and safe links without duplicates" do
    transport = %Pronotex.Pronote.Transport{
      root: "https://school.test/pronote",
      session: 123,
      key: <<1::128>>,
      iv: <<2::128>>
    }

    raw = %{
      "N" => "task",
      "PourLe" => %{"V" => "18/09/2026"},
      "descriptif" => %{
        "V" =>
          "<a href='https://example.org/exercice'>Exercice</a><a href='javascript:alert(1)'>Interdit</a>"
      },
      "ListePieceJointe" => %{
        "V" => [
          %{"G" => 1, "N" => "file-id", "L" => "À lire.pdf"},
          %{"G" => 0, "L" => "Exercice", "url" => "https://example.org/exercice"},
          %{"G" => 0, "L" => "Interdit", "url" => "data:text/html,test"}
        ]
      }
    }

    homework = Homework.parse(raw, "child", transport)

    assert [
             %{name: "À lire.pdf", type: :file, url: url},
             %{type: :link, url: "https://example.org/exercice"}
           ] = homework.resources

    uri = URI.parse(url)
    assert uri.query == "Session=123"
    [_, "pronote", "FichiersExternes", token, name] = String.split(uri.path, "/")
    assert URI.decode(name) == "À lire.pdf"

    assert token
           |> Pronotex.Pronote.Crypto.unhex()
           |> Pronotex.Pronote.Crypto.decrypt(transport.key, transport.iv)
           |> Jason.decode!() == %{"N" => "file-id", "Actif" => true}
  end

  test "homework without attachments has no resource links" do
    assert Homework.parse(%{"N" => "task", "PourLe" => %{"V" => "18/09/2026"}}, "child").resources ==
             []
  end

  test "Saturday includes Monday, but not Tuesday" do
    assert Homework.urgent_until(~D[2026-09-19]) == ~D[2026-09-21]
  end

  test "other days include the following calendar day" do
    assert Homework.urgent_until(~D[2026-09-18]) == ~D[2026-09-19]
    assert Homework.urgent_until(~D[2026-09-20]) == ~D[2026-09-21]
    assert Homework.urgent_until(~D[2026-09-21]) == ~D[2026-09-22]
  end
end
