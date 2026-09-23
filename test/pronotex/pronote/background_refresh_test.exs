defmodule Pronotex.Pronote.BackgroundRefreshTest do
  use ExUnit.Case, async: false
  alias Pronotex.Pronote.BackgroundRefresh

  setup do
    previous = Application.get_env(:pronotex, :background_refresh)
    Application.put_env(:pronotex, :background_refresh, true)
    on_exit(fn -> Application.put_env(:pronotex, :background_refresh, previous) end)
    :ok
  end

  test "quiet hours include 22:00 and end exactly at 07:00" do
    for hour <- [0, 1, 6, 22, 23],
        do: refute(BackgroundRefresh.daytime?({{2026, 9, 23}, {hour, 0, 0}}))

    for hour <- [7, 12, 21], do: assert(BackgroundRefresh.daytime?({{2026, 9, 23}, {hour, 0, 0}}))
    refute BackgroundRefresh.daytime?({{2026, 9, 23}, {6, 59, 59}})
    assert BackgroundRefresh.daytime?({{2026, 9, 23}, {21, 59, 59}})
  end

  test "night ticks do not start work and morning ticks resume it" do
    owner = self()
    {:ok, clock} = Agent.start_link(fn -> false end)

    worker =
      start_supervised!(
        {BackgroundRefresh,
         name: nil,
         interval: 20,
         allowed?: fn -> Agent.get(clock, & &1) end,
         run: fn -> send(owner, :refreshed) end}
      )

    send(worker, :refresh)
    :sys.get_state(worker)
    refute_receive :refreshed, 80
    Agent.update(clock, fn _ -> true end)
    assert_receive :refreshed, 500
    Agent.update(clock, fn _ -> false end)
    stop_supervised(BackgroundRefresh)
    Agent.stop(clock)
  end

  test "an account is not resolved or invalidated at night" do
    assert :ok =
             BackgroundRefresh.refresh_account(%{id: "nonexistent"}, allowed?: fn -> false end)
  end

  test "timer starts a cycle without a browser, and running cycles do not overlap" do
    owner = self()

    worker =
      start_supervised!(
        {BackgroundRefresh,
         name: nil,
         interval: 30,
         allowed?: fn -> true end,
         run: fn ->
           send(owner, {:cycle, self()})

           receive do
             :finish -> :ok
           end
         end}
      )

    assert_receive {:cycle, first}, 500
    send(worker, :refresh)
    :sys.get_state(worker)
    refute_receive {:cycle, _}, 80
    send(first, :finish)
    assert_receive {:cycle, second}, 500
    refute first == second
  end

  test "a crashed cycle does not kill the scheduler or prevent subsequent cycles" do
    owner = self()

    worker =
      start_supervised!(
        {BackgroundRefresh,
         name: nil,
         interval: 30,
         allowed?: fn -> true end,
         run: fn ->
           send(owner, {:cycle, self()})

           receive do
             :finish -> :ok
           end
         end}
      )

    assert_receive {:cycle, first}, 500
    Process.exit(first, :kill)
    assert_receive {:cycle, second}, 500
    assert Process.alive?(worker)
    refute first == second
  end
end
