defmodule Pronotex.Pronote.BackgroundRefresh do
  @moduledoc "Refreshes configured profiles every five minutes, independently of browser connections."
  use GenServer
  require Logger
  alias Pronotex.Pronote
  alias Pronotex.Pronote.{ReadCache, Session}

  @interval :timer.minutes(5)
  @kinds [:lessons, :events, :grades, :discussions, :parent_discussions]

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: Keyword.get(options, :name, __MODULE__))
  end

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)

    if Application.get_env(:pronotex, :background_refresh, true) do
      interval = Keyword.get(options, :interval, @interval)
      timer = Process.send_after(self(), :refresh, interval)

      {:ok,
       %{
         interval: interval,
         timer: timer,
         task: nil,
         allowed?: Keyword.get(options, :allowed?, &daytime?/0),
         run: Keyword.get(options, :run, &refresh_all/0)
       }}
    else
      :ignore
    end
  end

  @impl true
  def handle_info(:refresh, state) do
    Process.cancel_timer(state.timer)
    timer = Process.send_after(self(), :refresh, state.interval)

    task =
      state.task ||
        if(state.allowed?.(), do: Task.Supervisor.async_nolink(Pronotex.RefreshTasks, state.run))

    {:noreply, %{state | timer: timer, task: task}}
  end

  def handle_info({ref, _result}, %{task: %{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | task: nil}}
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{task: %{ref: ref}} = state) do
    Logger.warning("Background PRONOTE refresh failed; retrying next cycle")
    {:noreply, %{state | task: nil}}
  end

  @impl true
  def terminate(_reason, %{task: task}) do
    if task, do: Task.Supervisor.terminate_child(Pronotex.RefreshTasks, task.pid)
    :ok
  end

  @doc "Background reads run from 07:00 inclusive to 22:00 exclusive, in the server's TZ."
  def daytime?(time \\ :calendar.local_time())
  def daytime?({_date, {hour, _minute, _second}}), do: hour >= 7 and hour < 22

  def refresh_all do
    Enum.each(Pronotex.Accounts.all(), fn account ->
      try do
        case refresh_account(account) do
          :ok -> :ok
          {:error, _} -> Logger.warning("Background PRONOTE profile login failed")
        end
      rescue
        _ -> Logger.warning("Background PRONOTE profile refresh failed")
      catch
        :exit, _ -> Logger.warning("Background PRONOTE profile session unavailable")
      end
    end)
  end

  def refresh_account(account, options \\ []) do
    allowed? = Keyword.get(options, :allowed?, &daytime?/0)
    if allowed?.(), do: refresh_active_account(account, options, allowed?), else: :ok
  end

  defp refresh_active_account(account, options, allowed?) do
    server = Keyword.get_lazy(options, :server, fn -> Session.for_account(account.id) end)
    today = Keyword.get(options, :today, Date.utc_today())
    week = Date.beginning_of_week(today)
    ReadCache.invalidate({:owner_kinds, server, @kinds})

    with {:ok, children} <- Pronote.children(server) do
      results =
        Enum.flat_map(children, fn child ->
          # Resolve the resource again before each read, because session renewal
          # can replace PRONOTE identifiers in the middle of a cycle.
          operations = [
            {:lessons, [week, Date.add(week, 6)]},
            {:events, []},
            {:grades, [nil]}
          ]

          operations =
            if account.role == :child or Pronote.homework_writable?(child),
              do: operations ++ [{:discussions, []}],
              else: operations

          Enum.map(operations, fn {operation, args} ->
            if allowed?.(),
              do: read_child(server, child.name, operation, args, allowed?),
              else: :skipped
          end)
        end)

      results =
        if account.role == :parent and allowed?.(),
          do: [Pronote.parent_discussions(server) | results],
          else: results

      if Enum.any?(results, &match?({:ok, _}, &1)) do
        Phoenix.PubSub.broadcast(
          Pronotex.PubSub,
          "pronote:refresh",
          {:pronote_refreshed, account.id}
        )
      end

      if Enum.any?(results, &match?({:error, _}, &1)),
        do: Logger.warning("Some background PRONOTE reads failed; retrying next cycle")

      :ok
    end
  end

  defp read_child(server, name, operation, args, allowed?, retry? \\ true) do
    with true <- allowed?.(),
         {:ok, children} <- Pronote.children(server),
         [child] <- Enum.filter(children, &(&1.name == name)),
         true <- allowed?.() do
      case apply(Pronote, operation, [child.id | args] ++ [server]) do
        {:error, %Pronotex.Pronote.Error{reason: :child_not_found}} when retry? ->
          read_child(server, name, operation, args, allowed?, false)

        result ->
          result
      end
    else
      _ -> {:error, :child_unavailable}
    end
  end
end
