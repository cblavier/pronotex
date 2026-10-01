defmodule Pronotex.Auth.Session do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:token_hash, :binary, autogenerate: false}
  schema "auth_sessions" do
    field(:account_id, :string)
    field(:expires_at, :integer)
  end
end
