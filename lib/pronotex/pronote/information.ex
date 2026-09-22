defmodule Pronotex.Pronote.Information do
  @moduledoc "Information and survey notices, without submitting survey responses."
  alias Pronotex.Pronote.LessonContent

  def reference(raw) do
    %{
      "N" => raw["N"],
      "genrePublic" => raw["genrePublic"],
      "public" => get_in(raw, ["public", "V"])
    }
  end

  def id(raw) do
    "notice-" <>
      (:crypto.hash(:sha256, :erlang.term_to_binary(reference(raw)))
       |> Base.url_encode64(padding: false))
  end

  def acknowledgement_questions(detail) do
    (get_in(detail, ["detailsActualite", "listeQuestions", "V"]) || [])
    |> Enum.filter(&(&1["genreReponse"] == 0))
  end

  def acknowledged?(question), do: get_in(question, ["reponse", "V", "avecReponse"]) == true

  def acknowledgement_payload(detail) do
    for question <- acknowledgement_questions(detail),
        not acknowledged?(question),
        response = get_in(question, ["reponse", "V"]),
        is_map(response),
        response["estRepondant"] != false do
      %{
        "N" => question["N"],
        "E" => 2,
        "genreReponse" => 0,
        "reponse" =>
          Map.merge(Map.take(response, ["N", "G"]), %{
            "E" => 2,
            "avecReponse" => true,
            "valeurReponse" => ""
          })
      }
    end
  end

  def parse(raw, detail, transport) do
    date = get_in(raw, ["dateCreation", "V"]) || ""

    messages =
      for question <- get_in(detail, ["detailsActualite", "listeQuestions", "V"]) || [] do
        content =
          LessonContent.parse(
            %{
              "descriptif" => question["texte"],
              "ListePieceJointe" => question["listePiecesJointes"]
            },
            transport
          )

        %{
          id: question["N"],
          author: raw["auteur"] || "",
          date: date,
          content: content.description,
          resources: content.resources,
          title: question["titre"] || "",
          choices: Enum.map(get_in(question, ["listeChoix", "V"]) || [], &(&1["L"] || ""))
        }
      end

    acknowledgement = acknowledgement_questions(detail)
    acknowledged = acknowledgement != [] and Enum.all?(acknowledgement, &acknowledged?/1)

    %{
      acknowledgement_required: acknowledgement != [] and raw["estSondage"] != true,
      acknowledged: acknowledged,
      can_acknowledge: raw["estSondage"] != true and acknowledgement_payload(detail) != [],
      id: id(raw),
      kind: if(raw["estSondage"] == true, do: :survey, else: :information),
      subject: raw["L"] || "Sans objet",
      author: raw["auteur"] || "",
      date: date,
      unread: if(raw["lue"] == true, do: 0, else: 1),
      messages: messages,
      preview: messages |> Enum.map_join(" ", & &1.content) |> String.slice(0, 160)
    }
  end
end
