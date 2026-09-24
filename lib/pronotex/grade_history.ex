defmodule Pronotex.GradeHistory do
  @moduledoc "Persistent observations of PRONOTE grades and official averages, independent of login profiles."
  import Ecto.Query
  alias Pronotex.Repo
  alias Pronotex.GradeHistory.{Scope, Grade, Revision, AverageSnapshot}
  alias Pronotex.Pronote.{Grades, Lesson}

  def context(client, student_id, report) do
    # Resource IDs rotate on login; identify an unambiguous child by full name.
    first_day = Lesson.date(client.general["PremierLundi"]["V"])
    last_day = Lesson.date(client.general["DerniereDate"]["V"])

    %{
      school_url: String.trim_trailing(client.transport.root, "/"),
      student_id: stable_student_id(client, student_id),
      school_year: "#{first_day.year}-#{last_day.year}",
      period: Grades.period_key(report.period)
    }
  end

  defp stable_student_id(client, raw_id) do
    children = client.children || []
    child = Enum.find(children, &(&1["N"] == raw_id))
    name = if child, do: normalize_name(child["L"])

    if name && name != "" && Enum.count(children, &(normalize_name(&1["L"]) == name)) == 1 do
      "name:" <> Base.url_encode64(:crypto.hash(:sha256, name), padding: false)
    else
      raw_id
    end
  end

  defp normalize_name(name),
    do:
      (name || "")
      |> String.normalize(:nfc)
      |> String.downcase()
      |> String.split()
      |> Enum.sort()
      |> Enum.join(" ")

  @doc "Record one fresh remote response atomically; repeat observations do not duplicate history."
  def record(context, report, observed_at \\ DateTime.utc_now(), options \\ []) do
    Repo.transaction(fn ->
      legacy = Keyword.get(options, :legacy_context)

      scope =
        Repo.get_by(Scope, context) ||
          (legacy && Repo.get_by(Scope, legacy)) || Repo.insert!(struct!(Scope, context))

      scope =
        if scope.student_id != context.student_id,
          do: scope |> Ecto.Changeset.change(student_id: context.student_id) |> Repo.update!(),
          else: scope

      Enum.each(report.grades, &record_grade(scope.id, &1, observed_at))
      record_averages(scope.id, report, observed_at)
      scope.id
    end)
  end

  def grades(context) do
    case Repo.get_by(Scope, context) do
      nil ->
        []

      scope ->
        Repo.all(
          from(g in Grade,
            where: g.scope_id == ^scope.id,
            order_by: [asc: g.graded_on, asc: g.id]
          )
        )
    end
  end

  @doc "Sort current marks by publication (first observation when unavailable), newest first."
  def by_publication(context, current_grades) do
    history = grades(context)
    by_id = Map.new(history, &{&1.pronote_id, &1})

    # Resource IDs can rotate across sessions. Reuse the earliest observation of
    # an otherwise identical mark, ignoring changing class statistics.
    by_content = Enum.group_by(history, &grade_identity(&1.data))

    Enum.sort_by(
      current_grades,
      fn grade ->
        matches = Map.get(by_content, grade_identity(json(grade)), [])
        existing = Map.get(by_id, grade.id)
        matches = if existing, do: [existing | matches], else: matches

        published_at =
          Map.get(grade, :published_at) ||
            matches
            |> Enum.map(& &1.published_at)
            |> Enum.min(DateTime, fn -> nil end)

        timestamp =
          if published_at,
            do: DateTime.to_unix(published_at, :microsecond),
            else: DateTime.to_unix(DateTime.new!(grade.date, ~T[00:00:00]), :microsecond)

        {timestamp, Date.to_gregorian_days(grade.date), grade.id}
      end,
      :desc
    )
  end

  defp grade_identity(data),
    do: Map.drop(data, ["id", "average", "min", "max", "published_at"])

  def averages(context) do
    case Repo.get_by(Scope, context) do
      nil ->
        []

      scope ->
        Repo.all(
          from(s in AverageSnapshot,
            where: s.scope_id == ^scope.id,
            order_by: [asc: s.observed_at, asc: s.id]
          )
        )
    end
  end

  def revisions(grade_id) do
    Repo.all(
      from(r in Revision,
        where: r.grade_id == ^grade_id,
        order_by: [asc: r.observed_at, asc: r.id]
      )
    )
  end

  defp record_grade(scope_id, grade, observed_at) do
    data = json(grade)
    existing = Repo.get_by(Grade, scope_id: scope_id, pronote_id: grade.id)

    if is_nil(existing) or existing.data != data do
      # The current PRONOTE response does not expose a verified publication date.
      # Keep the fallback explicit, and never move it forward on subsequent reads.
      published_at = Map.get(grade, :published_at)

      attrs = %{
        graded_on: grade.date,
        published_at: published_at || (existing && existing.published_at) || observed_at,
        publication_estimated:
          is_nil(published_at) and (is_nil(existing) or existing.publication_estimated),
        data: data
      }

      saved =
        if existing do
          existing |> Ecto.Changeset.change(attrs) |> Repo.update!()
        else
          %Grade{scope_id: scope_id, pronote_id: grade.id, first_seen_at: observed_at}
          |> Ecto.Changeset.change(attrs)
          |> Repo.insert!()
        end

      Repo.insert!(%Revision{grade_id: saved.id, observed_at: observed_at, data: data})
    end
  end

  defp record_averages(scope_id, report, observed_at) do
    data =
      report
      |> Map.take([:overall, :class_overall, :overall_out_of, :averages])
      |> Map.update!(:averages, &Enum.sort_by(&1, fn average -> average.id end))
      |> json()

    latest =
      Repo.one(
        from(s in AverageSnapshot,
          where: s.scope_id == ^scope_id,
          order_by: [desc: s.id],
          limit: 1
        )
      )

    if is_nil(latest) or latest.data != data do
      Repo.insert!(%AverageSnapshot{scope_id: scope_id, observed_at: observed_at, data: data})
    end
  end

  defp json(value), do: value |> Jason.encode!() |> Jason.decode!()
end
