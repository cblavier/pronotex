defmodule Pronotex.Repo do
  use Ecto.Repo, otp_app: :pronotex, adapter: Ecto.Adapters.SQLite3

  @impl true
  def init(_type, config) do
    database = Keyword.fetch!(config, :database)
    if database != ":memory:", do: File.mkdir_p!(Path.dirname(database))
    {:ok, config}
  end
end
