defmodule Pronotex.Repo.Migrations.CreateGradeHistory do
  use Ecto.Migration

  def change do
    create table(:grade_scopes) do
      add :school_url, :text, null: false
      add :student_id, :string, null: false
      add :school_year, :string, null: false
      add :period, :string, null: false
    end

    create unique_index(:grade_scopes, [:school_url, :student_id, :school_year, :period])

    create table(:historical_grades) do
      add :scope_id, references(:grade_scopes), null: false
      add :pronote_id, :string, null: false
      add :graded_on, :date, null: false
      add :published_at, :utc_datetime_usec, null: false
      add :first_seen_at, :utc_datetime_usec, null: false
      add :publication_estimated, :boolean, null: false
      add :data, :map, null: false
    end

    create unique_index(:historical_grades, [:scope_id, :pronote_id])

    create table(:grade_revisions) do
      add :grade_id, references(:historical_grades), null: false
      add :observed_at, :utc_datetime_usec, null: false
      add :data, :map, null: false
    end

    create index(:grade_revisions, [:grade_id, :observed_at])

    create table(:average_snapshots) do
      add :scope_id, references(:grade_scopes), null: false
      add :observed_at, :utc_datetime_usec, null: false
      add :data, :map, null: false
    end

    create index(:average_snapshots, [:scope_id, :observed_at])
  end
end
