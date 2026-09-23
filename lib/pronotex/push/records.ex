defmodule Pronotex.Push.Setting do
  use Ecto.Schema
  @primary_key {:key, :string, autogenerate: false}
  @derive {Inspect, except: [:value]}
  schema "push_settings" do
    field(:value, :map)
  end
end

defmodule Pronotex.Push.Subscription do
  use Ecto.Schema
  @derive {Inspect, except: [:endpoint, :auth, :p256dh, :account_fingerprint]}
  schema "push_subscriptions" do
    field(:account_id, :string)
    field(:account_fingerprint, :binary)
    field(:endpoint, :string)
    field(:p256dh, :string)
    field(:auth, :string)
  end
end

defmodule Pronotex.Push.Baseline do
  use Ecto.Schema
  @primary_key {:key, :string, autogenerate: false}
  schema "push_baselines" do
    field(:counts, :map)
  end
end

defmodule Pronotex.Push.Delivery do
  use Ecto.Schema

  schema "push_deliveries" do
    field(:subscription_id, :id)
    field(:payload, :map)
    field(:attempts, :integer, default: 0)
    field(:due_at, :utc_datetime_usec)
    field(:expires_at, :utc_datetime_usec)
  end
end
