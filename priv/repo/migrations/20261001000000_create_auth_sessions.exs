defmodule Pronotex.Repo.Migrations.CreateAuthSessions do
  use Ecto.Migration

  def change do
    create table(:auth_sessions, primary_key: false) do
      add(:token_hash, :binary, primary_key: true)
      add(:account_id, :string, null: false)
      add(:expires_at, :bigint, null: false)
    end

    create(index(:auth_sessions, [:expires_at]))
  end
end
