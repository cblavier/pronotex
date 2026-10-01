defmodule Pronotex.NotificationBanners do
  @moduledoc "Ephemeral, account-scoped banners shared by all connected devices."
  use GenServer
  alias Pronotex.Accounts

  def start_link(options),
    do: GenServer.start_link(__MODULE__, %{}, name: Keyword.get(options, :name, __MODULE__))

  def subscribe(account_id),
    do: Phoenix.PubSub.subscribe(Pronotex.PubSub, topic(scope(account_id)))

  def list(account_id, server \\ __MODULE__),
    do: GenServer.call(server, {:list, scope(account_id)})

  def activate(account_id, kind, url, server \\ __MODULE__)
      when kind in ["grades", "cancellation"] do
    GenServer.call(server, {:activate, scope(account_id), kind, url})
  end

  def dismiss(account_id, tag, server \\ __MODULE__),
    do: GenServer.call(server, {:dismiss, scope(account_id), tag})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:list, scope}, _from, state), do: {:reply, Map.get(state, scope, []), state}

  def handle_call({:activate, scope, kind, url}, _from, state) do
    # One banner per child and kind; a new tag protects newer events from stale clicks.
    banner = %{"kind" => kind, "url" => url, "tag" => Ecto.UUID.generate()}
    path = URI.parse(url).path
    previous = Map.get(state, scope, [])

    banners =
      Enum.reject(previous, &(&1["kind"] == kind and URI.parse(&1["url"]).path == path)) ++
        [banner]

    broadcast(scope)
    {:reply, :ok, Map.put(state, scope, banners)}
  end

  def handle_call({:dismiss, scope, tag}, _from, state) do
    banners = Enum.reject(Map.get(state, scope, []), &(&1["tag"] == tag))
    state = if banners == [], do: Map.delete(state, scope), else: Map.put(state, scope, banners)
    broadcast(scope)
    {:reply, :ok, state}
  end

  defp scope(account_id), do: {account_id, Accounts.fingerprint(account_id)}

  defp topic(scope),
    do: "notification-banners:" <> Base.url_encode64(:erlang.term_to_binary(scope))

  defp broadcast(scope),
    do: Phoenix.PubSub.broadcast(Pronotex.PubSub, topic(scope), :notification_banners_changed)
end
