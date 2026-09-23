defmodule Pronotex.Repo.Migrations.CreatePushNotifications do
  use Ecto.Migration

  def change do
    create table(:push_settings, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :map, null: false
    end

    create table(:push_subscriptions) do
      add :account_id, :string, null: false
      add :account_fingerprint, :binary, null: false
      add :endpoint, :text, null: false
      add :p256dh, :string, null: false
      add :auth, :string, null: false
    end
    create unique_index(:push_subscriptions, [:endpoint])

    create table(:push_baselines, primary_key: false) do
      add :key, :string, primary_key: true
      add :counts, :map, null: false
    end

    create table(:push_deliveries) do
      add :subscription_id, references(:push_subscriptions, on_delete: :delete_all), null: false
      add :payload, :map, null: false
      add :attempts, :integer, null: false, default: 0
      add :due_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
    end
    create index(:push_deliveries, [:due_at])
  end
end
