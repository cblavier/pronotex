defmodule Pronotex.GradeHistory.Scope do
  use Ecto.Schema

  schema "grade_scopes" do
    field(:school_url, :string)
    field(:student_id, :string)
    field(:school_year, :string)
    field(:period, :string)
  end
end

defmodule Pronotex.GradeHistory.Grade do
  use Ecto.Schema

  schema "historical_grades" do
    field(:scope_id, :id)
    field(:pronote_id, :string)
    field(:graded_on, :date)
    field(:published_at, :utc_datetime_usec)
    field(:first_seen_at, :utc_datetime_usec)
    field(:publication_estimated, :boolean)
    field(:data, :map)
  end
end

defmodule Pronotex.GradeHistory.Revision do
  use Ecto.Schema

  schema "grade_revisions" do
    field(:grade_id, :id)
    field(:observed_at, :utc_datetime_usec)
    field(:data, :map)
  end
end

defmodule Pronotex.GradeHistory.AverageSnapshot do
  use Ecto.Schema

  schema "average_snapshots" do
    field(:scope_id, :id)
    field(:observed_at, :utc_datetime_usec)
    field(:data, :map)
  end
end
