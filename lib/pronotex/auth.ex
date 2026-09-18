defmodule Pronotex.Auth do
  use GenServer
  @lifetime 12 * 60 * 60

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def init(_), do: {:ok, %{failures: 0, retry_at: 0}}
  def pin, do: Application.get_env(:pronotex, :pin_code)
  def enabled?, do: pin() not in [nil, ""]
  def configured?, do: is_binary(pin()) and Regex.match?(~r/\A[0-9]{8}\z/, pin())
  def now, do: System.system_time(:second)
  def expires_at(session), do: session["auth_expires_at"] || 0

  def session do
    %{"auth_expires_at" => now() + @lifetime, "auth_version" => version()}
  end

  def valid?(session) do
    not enabled?() or
      (configured?() and is_integer(expires_at(session)) and expires_at(session) > now() and
         session["auth_version"] == version())
  end

  defp version do
    secret = Application.fetch_env!(:pronotex, PronotexWeb.Endpoint)[:secret_key_base]
    :crypto.mac(:hmac, :sha256, secret, pin() || "") |> Base.encode64()
  end

  def attempt(value), do: GenServer.call(__MODULE__, {:attempt, value})

  # One shared counter: clearing cookies or changing IP cannot bypass the delay.
  def handle_call({:attempt, value}, _, state) do
    time = System.monotonic_time(:second)

    cond do
      not configured?() ->
        {:reply, :unconfigured, state}

      state.failures >= 3 and state.retry_at > time ->
        {:reply, {:wait, state.retry_at - time}, state}

      is_binary(value) and byte_size(value) == 8 and Plug.Crypto.secure_compare(value, pin()) ->
        {:reply, :ok, %{failures: 0, retry_at: 0}}

      true ->
        failures = state.failures + 1
        delay = max(failures - 2, 0) * 60
        {:reply, {:invalid, delay}, %{failures: failures, retry_at: time + delay}}
    end
  end
end
