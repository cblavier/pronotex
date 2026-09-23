defmodule Pronotex.Pronote.ReadCache do
  @moduledoc "Bounded, memory-only cache of successful reads; never refreshes in the background."
  use GenServer

  def start_link(options),
    do: GenServer.start_link(__MODULE__, options, name: Keyword.get(options, :name, __MODULE__))

  def fetch(key, server \\ __MODULE__), do: GenServer.call(server, {:fetch, key})

  def put(key, value, ttl, generation, server \\ __MODULE__),
    do: GenServer.call(server, {:put, key, value, ttl, generation})

  def invalidate(scope, server \\ __MODULE__), do: GenServer.call(server, {:invalidate, scope})

  def ttl(kind) when kind in [:lessons, :events], do: 300_000
  def ttl(kind) when kind in [:homework, :discussions, :parent_discussions], do: 300_000
  def ttl(:grades), do: 300_000
  def ttl(:menus), do: 1_800_000

  @impl true
  def init(options) do
    {:ok,
     %{
       entries: %{},
       generation: make_ref(),
       kind_generations: %{},
       limit: Keyword.get(options, :limit, 256),
       clock: Keyword.get(options, :clock, fn -> System.monotonic_time(:millisecond) end)
     }}
  end

  @impl true
  def handle_call({:fetch, key}, _from, state) do
    state = prune(state)

    reply =
      case Map.get(state.entries, key) do
        nil -> {:miss, generation(state, key)}
        {value, _, _} -> {:hit, value}
      end

    {:reply, reply, state}
  end

  def handle_call({:put, key, value, ttl, generation}, _from, state) do
    state = prune(state)

    if generation == generation(state, key) do
      now = state.clock.()
      entries = Map.put(state.entries, key, {value, now + ttl, now})

      entries =
        if map_size(entries) > state.limit do
          {oldest, _} = Enum.min_by(entries, fn {_, {_, _, inserted}} -> inserted end)
          Map.delete(entries, oldest)
        else
          entries
        end

      {:reply, :ok, %{state | entries: entries}}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:invalidate, {:kind, kind}}, _from, state) do
    entries = Map.reject(state.entries, fn {key, _} -> kind(key) == kind end)
    generations = Map.put(state.kind_generations, kind, make_ref())
    {:reply, :ok, %{state | entries: entries, kind_generations: generations}}
  end

  def handle_call({:invalidate, scope}, _from, state) do
    entries =
      if scope == :all,
        do: %{},
        else: Map.reject(state.entries, fn {{owner, _}, _} -> owner == scope end)

    {:reply, :ok, %{state | entries: entries, generation: make_ref()}}
  end

  @impl true
  def format_status(status), do: %{status | state: :redacted}

  defp generation(state, key),
    do: {state.generation, Map.get(state.kind_generations, kind(key))}

  defp kind({_owner, {_identity, operation}}) when is_tuple(operation), do: elem(operation, 0)
  defp kind(_key), do: nil

  defp prune(state) do
    now = state.clock.()

    entries =
      Map.reject(state.entries, fn {{owner, _}, {_, expires, _}} ->
        expires <= now or not Process.alive?(owner)
      end)

    %{state | entries: entries}
  end
end
