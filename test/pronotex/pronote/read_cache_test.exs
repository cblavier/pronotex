defmodule Pronotex.Pronote.ReadCacheTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote.ReadCache

  setup do
    clock = start_supervised!({Agent, fn -> 0 end})

    cache =
      start_supervised!({ReadCache, name: nil, limit: 2, clock: fn -> Agent.get(clock, & &1) end})

    %{cache: cache, clock: clock}
  end

  test "expiry is based on age, not refreshed by a cache hit", %{cache: cache, clock: clock} do
    key = {self(), :lessons}
    {:miss, generation} = ReadCache.fetch(key, cache)
    ReadCache.put(key, :lessons, 60_000, generation, cache)
    Agent.update(clock, fn _ -> 59_999 end)
    assert {:hit, :lessons} = ReadCache.fetch(key, cache)
    Agent.update(clock, fn _ -> 60_000 end)
    assert {:miss, _} = ReadCache.fetch(key, cache)
  end

  for affected <- [:homework, :discussions, :parent_discussions] do
    test "#{affected} invalidation preserves unrelated caches and in-flight reads" do
      affected = unquote(affected)
      cache = start_supervised!({ReadCache, name: nil, limit: 20}, id: :category_cache)
      other = start_supervised!({Agent, fn -> nil end}, id: :other_profile)
      kinds = [:homework, :discussions, :parent_discussions, :lessons, :grades, :menus]

      pending =
        for kind <- kinds do
          for owner <- [self(), other] do
            key = {owner, {:identity, {kind, :existing}}}
            {:miss, generation} = ReadCache.fetch(key, cache)
            ReadCache.put(key, :cached, 60_000, generation, cache)
          end

          key = {self(), {:identity, {kind, :in_flight}}}
          {:miss, generation} = ReadCache.fetch(key, cache)
          {kind, key, generation}
        end

      ReadCache.invalidate({:kind, affected}, cache)

      for {kind, key, generation} <- pending do
        ReadCache.put(key, :result, 60_000, generation, cache)

        if kind == affected do
          assert {:miss, _} = ReadCache.fetch(key, cache)

          for owner <- [self(), other] do
            assert {:miss, _} = ReadCache.fetch({owner, {:identity, {kind, :existing}}}, cache)
          end
        else
          assert {:hit, :result} = ReadCache.fetch(key, cache)

          for owner <- [self(), other] do
            assert {:hit, :cached} =
                     ReadCache.fetch({owner, {:identity, {kind, :existing}}}, cache)
          end
        end
      end
    end
  end

  test "bounded capacity evicts the oldest entry", %{cache: cache, clock: clock} do
    for number <- 1..3 do
      Agent.update(clock, fn _ -> number end)
      key = {self(), number}
      {:miss, generation} = ReadCache.fetch(key, cache)
      ReadCache.put(key, number, 60_000, generation, cache)
    end

    assert {:miss, _} = ReadCache.fetch({self(), 1}, cache)
    assert {:hit, 2} = ReadCache.fetch({self(), 2}, cache)
    assert {:hit, 3} = ReadCache.fetch({self(), 3}, cache)
  end

  test "invalidation rejects in-flight stale results and isolates profile values", %{cache: cache} do
    other = start_supervised!({Agent, fn -> nil end}, id: :other)
    key = {self(), :same_operation}
    other_key = {other, :same_operation}
    {:miss, generation} = ReadCache.fetch(key, cache)
    ReadCache.put(key, :mine, 60_000, generation, cache)
    ReadCache.put(other_key, :theirs, 60_000, generation, cache)
    ReadCache.invalidate(self(), cache)
    ReadCache.put(key, :stale, 60_000, generation, cache)
    assert {:miss, _} = ReadCache.fetch(key, cache)
    assert {:hit, :theirs} = ReadCache.fetch(other_key, cache)
    {:miss, new_generation} = ReadCache.fetch(key, cache)
    ReadCache.invalidate(:all, cache)
    ReadCache.put(key, :racing_read, 60_000, new_generation, cache)
    assert {:miss, _} = ReadCache.fetch(key, cache)
    assert {:miss, _} = ReadCache.fetch(other_key, cache)
  end
end
