defmodule Pronotex.Push.Worker do
  @moduledoc false
  use GenServer
  require Logger

  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: __MODULE__)

  def deliver_now do
    if Application.get_env(:pronotex, :push_delivery, true),
      do: GenServer.cast(__MODULE__, :deliver)

    :ok
  end

  @impl true
  def handle_cast(:deliver, state) do
    deliver()
    {:noreply, state}
  end

  @impl true
  def init(_) do
    Pronotex.Push.configure()
    schedule()
    {:ok, nil}
  end

  @impl true
  def handle_info(:deliver, state) do
    deliver()
    schedule()
    {:noreply, state}
  end

  defp deliver do
    try do
      Pronotex.Push.deliver_pending()
    rescue
      _ -> Logger.warning("Push delivery failed; pending notifications will be retried")
    end
  end

  defp schedule do
    if Application.get_env(:pronotex, :push_delivery, true),
      do: Process.send_after(self(), :deliver, 15_000)
  end
end
