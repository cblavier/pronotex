defmodule Pronotex.Pronote.Correspondence do
  @moduledoc "Read-only school-life entries from the correspondence book."
  alias Pronotex.Pronote.Lesson

  @categories %{
    13 => "Absence aux cours",
    14 => "Retard",
    21 => "Passage à l’infirmerie",
    22 => "Absence au repas",
    40 => "Dispense",
    41 => "Punition",
    42 => "Sanction",
    44 => "Absence à l’internat",
    71 => "Mesure conservatoire",
    73 => "Incident",
    105 => "Commission",
    114 => "Demande de dispense",
    121 => "Retard à l’internat"
  }

  def current?(entries) when is_list(entries),
    do: Enum.all?(entries, &(Map.get(&1, :presentation_version) == 2))

  def parse(raw) do
    category = category(raw)
    date = value(raw["date"] || raw["dateDebut"] || raw["dateDemande"]) || ""
    author = label(raw["demandeur"]) || "Vie scolaire"
    subject = nonempty(raw["L"]) || label(raw["nature"]) || category
    comment = value(raw["commentaire"]) || ""

    comment =
      if raw["estHTML"] == true, do: Pronotex.Pronote.HTMLText.parse(comment), else: comment

    content =
      [
        date_and_duration(raw),
        reason(raw),
        if(is_boolean(raw["justifie"]), do: nil, else: status(raw)),
        comment,
        value(raw["circonstances"]),
        value(raw["justification"])
      ]
      |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
      |> Enum.uniq()
      |> Enum.join("\n")

    # Pronote resource numbers are only unique within their resource kind.
    prefix = if raw["G"] == 46, do: "carnet-", else: "carnet-#{raw["G"]}-"
    id = prefix <> to_string(Map.fetch!(raw, "N"))

    %{
      id: id,
      kind: :correspondence,
      subject: subject,
      summary_title: subject,
      presentation_version: 2,
      end_date: value(raw["dateFin"]),
      author: author,
      date: date,
      category: category,
      justified: if(is_boolean(raw["justifie"]), do: raw["justifie"]),
      unread:
        if(raw["G"] == 46 and raw["avecARObservation"] == true and raw["estLue"] != true,
          do: 1,
          else: 0
        ),
      preview: String.slice(content, 0, 160),
      messages: [
        %{
          id: id,
          author: author,
          date: date,
          content: content,
          title: label(raw["matiere"]) || ""
        }
      ]
    }
  end

  defp category(%{"G" => 46} = raw) do
    case raw["genreObservation"] do
      0 -> "Défaut de carnet"
      1 -> "Observation"
      2 -> "Encouragement"
      _ -> "Autre observation"
    end
  end

  defp category(raw), do: Map.get(@categories, raw["G"], "Vie scolaire")

  defp date_and_duration(raw) do
    case single_day_absence(raw) do
      {from, to} ->
        duration = missed_classes(raw)

        "Le #{Calendar.strftime(from, "%d/%m/%Y")} de #{hour(from)} à #{hour(to)}" <>
          if(duration, do: " (#{duration})", else: "")

      nil ->
        [date_range(raw), missed_classes(raw)] |> Enum.reject(&is_nil/1) |> Enum.join("\n")
    end
  end

  defp single_day_absence(%{"G" => 13} = raw) do
    with from when is_binary(from) <- value(raw["dateDebut"]),
         to when is_binary(to) <- value(raw["dateFin"]) do
      from = Lesson.datetime(from)
      to = Lesson.datetime(to)
      if NaiveDateTime.to_date(from) == NaiveDateTime.to_date(to), do: {from, to}
    else
      _ -> nil
    end
  rescue
    _ in [Pronotex.Pronote.Error, ArgumentError] -> nil
  end

  defp single_day_absence(_), do: nil

  defp hour(date),
    do: "#{date.hour}h#{String.pad_leading(Integer.to_string(date.minute), 2, "0")}"

  defp date_range(raw) do
    from = value(raw["dateDebut"])
    to = value(raw["dateFin"])

    cond do
      is_binary(from) and is_binary(to) and from != to ->
        "Du #{format_date(from)} au #{format_date(to)}"

      is_binary(from) ->
        "Le #{format_date(from)}"

      true ->
        nil
    end
  end

  defp format_date(value) do
    value |> Lesson.datetime() |> Calendar.strftime("%d/%m/%Y à %Hh%M")
  rescue
    _ in [Pronotex.Pronote.Error, ArgumentError] -> value
  end

  defp missed_classes(raw) do
    case value(raw["NbrHeures"]) do
      hours when is_binary(hours) and hours not in ["", "0h00"] -> "#{hours} de cours manqués"
      _ -> nil
    end
  end

  defp reason(raw) do
    reasons =
      (value(raw["listeMotifs"]) || [])
      |> Enum.map(&label/1)
      |> Enum.reject(&is_nil/1)

    reasons = if reasons == [], do: [label(raw["motifParent"])], else: reasons

    case Enum.reject(reasons, &is_nil/1) do
      [] -> nil
      labels -> "Motif : " <> Enum.join(labels, ", ")
    end
  end

  defp status(%{"G" => kind} = raw) when kind in [13, 14] do
    noun = if kind == 13, do: "Absence", else: "Retard"

    cond do
      raw["aRegulariser"] == true ->
        "#{noun} à justifier"

      raw["enAttente"] == true and raw["reglee"] != true ->
        "#{noun} en attente"

      raw["justifie"] == true ->
        if(kind == 13, do: "Absence justifiée", else: "Retard justifié")

      raw["justifie"] == false ->
        if(kind == 13, do: "Absence non justifiée", else: "Retard non justifié")

      true ->
        nil
    end
  end

  defp status(_), do: nil
  defp nonempty(text) when is_binary(text), do: if(String.trim(text) != "", do: text)
  defp nonempty(_), do: nil
  defp label(raw) when is_map(raw), do: label_value(value(raw))
  defp label(_), do: nil
  defp label_value(raw) when is_map(raw), do: nonempty(raw["L"])
  defp label_value(_), do: nil
  defp value(%{"V" => value}), do: value
  defp value(value), do: value
end
