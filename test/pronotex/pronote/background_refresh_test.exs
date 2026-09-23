defmodule Pronotex.Pronote.BackgroundRefreshTest do
  use ExUnit.Case, async: false
  alias Pronotex.Pronote.BackgroundRefresh

  setup do
    previous = Application.get_env(:pronotex, :background_refresh)
    Application.put_env(:pronotex, :background_refresh, true)
    on_exit(fn -> Application.put_env(:pronotex, :background_refresh, previous) end)
    :ok
  end

  test "timer starts a cycle without a browser, and running cycles do not overlap" do
    owner = self()

    worker =
      start_supervised!(
        {BackgroundRefresh,
         name: nil,
         interval: 30,
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
