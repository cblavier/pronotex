defmodule Pronotex.Pronote.LessonContentTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote.{LessonContent, Crypto, Transport}

  test "nested blocks and empty paragraphs do not add blank lines" do
    content =
      LessonContent.parse(
        %{
          "descriptif" => %{
            "V" => "<div><p>Révision<br></p></div>\n<p>&nbsp;</p><div><p>Exercices</p></div>"
          }
        },
        nil
      )

    assert content.description == "Révision\nExercices"
  end

  test "preserves text and safe links while stripping executable markup" do
    content =
      LessonContent.parse(
        %{
          "L" => "Leçon",
          "descriptif" => %{
            "V" =>
              "<p>Première ligne</p><p>Suite <a href='https://example.org'>Lien</a></p><script>alert(1)</script><a href='javascript:alert(1)'>Interdit</a>"
          },
          "ListePieceJointe" => %{
            "V" => [%{"G" => 0, "L" => "Dangereux", "url" => "data:text/html,test"}]
          }
        },
        nil
      )

    assert content.description =~ "Première ligne\n"
    refute content.description =~ "alert(1)"
    assert [%{url: "https://example.org", type: :link}] = content.resources
  end

  test "builds a signed attachment URL from the active session" do
    transport = %Transport{
      root: "https://example.org/pronote",
      session: 123,
      key: <<1::128>>,
      iv: <<2::128>>
    }

    content =
      LessonContent.parse(
        %{
          "ListePieceJointe" => %{
            "V" => [%{"G" => 1, "N" => "file-id", "L" => "Mon fichier.pdf"}]
          }
        },
        transport
      )

    [file] = content.resources
    assert file.type == :file
    uri = URI.parse(file.url)
    assert uri.query == "Session=123"
    [_, "pronote", "FichiersExternes", token, name] = String.split(uri.path, "/")
    assert name == "Mon%20fichier.pdf"

    assert token
           |> Crypto.unhex()
           |> Crypto.decrypt(transport.key, transport.iv)
           |> Jason.decode!() == %{"N" => "file-id", "Actif" => true}
  end
end
