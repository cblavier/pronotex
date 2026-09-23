defmodule Pronotex.GradeHistoryTest do
  use ExUnit.Case, async: false
  alias Pronotex.{GradeHistory, Repo}
  alias Pronotex.GradeHistory.{Scope, Grade}

  @now ~U[2026-09-23 10:00:00.000000Z]
  @later ~U[2026-09-24 10:00:00.000000Z]

  setup do
    context = %{
      school_url: "https://history.test/pronote",
      student_id: "student-#{System.unique_integer([:positive])}",
      school_year: "2026-2027",
      period: "semester1"
    }

    report = %{
      grades: [%{id: "g1", subject: "Maths", date: ~D[2026-09-17], score: "14,5", out_of: "20"}],
      averages: [%{id: "maths", subject: "Maths", score: "14,5", out_of: "20"}],
      overall: "14,5",
      overall_out_of: "20",
      class_overall: "12"
    }

    %{context: context, report: report}
  end

  test "official history survives rotated student IDs and adopts a matching legacy scope", %{
    context: original,
    report: report
  } do
    client = %{
      transport: %{root: original.school_url},
      general: %{
        "PremierLundi" => %{"V" => "31/08/2026"},
        "DerniereDate" => %{"V" => "04/07/2027"}
      },
      children: [%{"N" => original.student_id, "L" => "HISTORY Unique Child"}]
    }

    report = Map.put(report, :period, "Semestre 1")
    context = GradeHistory.context(client, original.student_id, report)
    {:ok, old_id} = GradeHistory.record(original, report, @now)
    assert {:ok, ^old_id} = GradeHistory.record(context, report, @later, legacy_context: original)
    assert [snapshot] = GradeHistory.averages(context)
    assert snapshot.observed_at == @now
    rotated = %{client | children: [%{"N" => "new-session", "L" => "HISTORY Unique Child"}]}
    assert GradeHistory.context(rotated, "new-session", report) == context
    other_period = GradeHistory.context(rotated, "new-session", %{report | period: "Semestre 2"})
    assert GradeHistory.averages(other_period) == []
    assert GradeHistory.averages(%{context | school_year: "2027-2028"}) == []
  end

  test "initial import fills all dates and dates official averages at observation time", %{
    context: context,
    report: report
  } do
    assert {:ok, _} = GradeHistory.record(context, report, @now)
    assert [grade] = GradeHistory.grades(context)
    assert grade.graded_on == ~D[2026-09-17]
    assert grade.published_at == @now
    assert grade.first_seen_at == @now
    assert grade.publication_estimated
    assert [snapshot] = GradeHistory.averages(context)
    assert snapshot.observed_at == @now
    assert snapshot.data["overall"] == "14,5"
    assert [%{"score" => "14,5"}] = snapshot.data["averages"]
  end

  test "unchanged reads are deduplicated, corrections preserve first observation", %{
    context: context,
    report: report
  } do
    GradeHistory.record(context, report, @now)
    GradeHistory.record(context, report, @later)
    assert [_] = GradeHistory.averages(context)
    assert [grade] = GradeHistory.grades(context)
    assert [_] = GradeHistory.revisions(grade.id)

    revised = put_in(report, [:grades, Access.at(0), :score], "16")
    GradeHistory.record(context, %{revised | overall: "15"}, @later)
    assert [updated] = GradeHistory.grades(context)
    assert updated.first_seen_at == @now
    assert updated.published_at == @now
    assert updated.data["score"] == "16"
    assert [initial, correction] = GradeHistory.revisions(grade.id)
    assert initial.data["score"] == "14,5"
    assert correction.data["score"] == "16"
    assert correction.observed_at == @later
    assert [_, _] = GradeHistory.averages(context)

    # A return to an older value is a new event, not a global content deduplication.
    GradeHistory.record(context, report, ~U[2026-09-25 10:00:00.000000Z])
    assert [_, _, _] = GradeHistory.averages(context)
  end

  test "known publication dates replace estimates without changing first_seen_at", %{
    context: context,
    report: report
  } do
    GradeHistory.record(context, report, @now)
    published = ~U[2026-09-18 08:00:00.000000Z]

    report =
      update_in(report.grades, fn [grade] -> [Map.put(grade, :published_at, published)] end)

    GradeHistory.record(context, report, @later)
    assert [grade] = GradeHistory.grades(context)
    assert grade.published_at == published
    assert grade.first_seen_at == @now
    refute grade.publication_estimated
  end

  test "school, student, school year and period isolate observations", %{
    context: context,
    report: report
  } do
    for {key, value} <- [
          school_url: "https://other.test",
          student_id: "other",
          school_year: "2027-2028",
          period: "semester2"
        ] do
      other = Map.put(context, key, value)
      GradeHistory.record(other, report, @now)
      assert [_] = GradeHistory.grades(other)
    end

    assert [] = GradeHistory.grades(context)
  end

  test "concurrent profile observations create only one initial record", %{
    context: context,
    report: report
  } do
    results =
      1..8
      |> Task.async_stream(fn _ -> GradeHistory.record(context, report, @now) end)
      |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, {:ok, _}}, &1))
    assert [grade] = GradeHistory.grades(context)
    assert [_] = GradeHistory.revisions(grade.id)
    assert [_] = GradeHistory.averages(context)
  end

  test "a missing effective date rolls back the entire report", %{
    context: context,
    report: report
  } do
    invalid = %{id: "invalid", date: nil, score: "12"}

    assert_raise Exqlite.Error, fn ->
      GradeHistory.record(context, %{report | grades: report.grades ++ [invalid]}, @now)
    end

    assert Repo.get_by(Scope, context) == nil
    assert GradeHistory.grades(context) == []
    assert GradeHistory.averages(context) == []
  end

  test "the database rejects all three missing date columns", %{context: context} do
    scope = Repo.insert!(struct!(Scope, context))

    base = %{
      scope_id: scope.id,
      pronote_id: "required",
      graded_on: ~D[2026-09-17],
      published_at: @now,
      first_seen_at: @now,
      publication_estimated: true,
      data: %{}
    }

    for field <- [:graded_on, :published_at, :first_seen_at] do
      assert_raise Exqlite.Error, fn ->
        Repo.insert!(struct!(Grade, Map.put(base, field, nil)))
      end
    end
  end
end
