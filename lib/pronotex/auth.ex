defmodule Pronotex.Auth do
  use GenServer
  alias Pronotex.Accounts

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def init(_), do: {:ok, %{}}
  def enabled?, do: true
  def configured?, do: Accounts.all() != []
  def now, do: System.system_time(:second)
  def expires_at(session), do: session["auth_expires_at"] || 0
  def lifetime(false), do: 60 * 60
  def lifetime(true), do: 30 * 24 * 60 * 60

  def session(id \\ "family", remember \\ false) do
    %{
      "auth_account" => id,
      "auth_expires_at" => now() + lifetime(remember),
      "auth_version" => version(id)
    }
  end

  def valid?(session) do
    id = session["auth_account"]

    Accounts.get(id) != nil and is_integer(expires_at(session)) and expires_at(session) > now() and
      is_binary(session["auth_version"]) and session["auth_version"] == version(id)
  end

  defp version(id) do
    secret = Application.fetch_env!(:pronotex, PronotexWeb.Endpoint)[:secret_key_base]
    :crypto.mac(:hmac, :sha256, secret, Accounts.fingerprint(id) || "missing") |> Base.encode64()
  end

  def attempt(id, value), do: GenServer.call(__MODULE__, {:attempt, id, value})

  # Per-profile counters cannot be bypassed by deleting a cookie or changing IP.
  def handle_call({:attempt, id, value}, _, states) do
    time = System.monotonic_time(:second)
    state = Map.get(states, id, %{failures: 0, retry_at: time})
    pin = Accounts.pin(id)

    cond do
      is_nil(Accounts.get(id)) ->
        {:reply, :unconfigured, states}

      state.failures >= 3 and state.retry_at > time ->
        {:reply, {:wait, state.retry_at - time}, states}

      is_binary(value) and byte_size(value) == byte_size(pin) and
          Plug.Crypto.secure_compare(value, pin) ->
        {:reply, :ok, Map.delete(states, id)}

      true ->
        failures = state.failures + 1
        delay = max(failures - 2, 0) * 60

        {:reply, {:invalid, delay},
         Map.put(states, id, %{failures: failures, retry_at: time + delay})}
    end
  end
end
