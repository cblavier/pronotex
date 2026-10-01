defmodule Pronotex.Auth do
  use GenServer
  import Ecto.Query
  alias Pronotex.{Accounts, Repo}
  alias Pronotex.Auth.Session

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def init(_), do: {:ok, %{}}
  def enabled?, do: true
  def configured?, do: Accounts.all() != []
  def now, do: System.system_time(:second)
  def expires_at(session), do: session["auth_expires_at"] || 0
  def lifetime(false), do: 60 * 60
  def lifetime(true), do: 30 * 24 * 60 * 60

  def session(id \\ "family", remember \\ false) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    expires = now() + lifetime(remember)
    cutoff = now()
    Repo.delete_all(from(s in Session, where: s.expires_at <= ^cutoff))
    Repo.insert!(%Session{token_hash: token_hash(token), account_id: id, expires_at: expires})

    %{
      "auth_session_id" => token,
      "auth_account" => id,
      "auth_expires_at" => expires,
      "auth_version" => version(id)
    }
  end

  def valid?(session) do
    id = session["auth_account"]

    Accounts.get(id) != nil and is_integer(expires_at(session)) and expires_at(session) > now() and
      is_binary(session["auth_version"]) and session["auth_version"] == version(id) and
      registered?(session)
  end

  # Only the hash is stored; removing it revokes every copy of this cookie,
  # independently of other devices and across application restarts.
  def revoke(session) do
    if is_binary(session["auth_session_id"]) do
      hash = token_hash(session["auth_session_id"])
      Repo.delete_all(from(s in Session, where: s.token_hash == ^hash))
    end

    :ok
  end

  defp registered?(%{
         "auth_session_id" => token,
         "auth_account" => id,
         "auth_expires_at" => expires
       })
       when is_binary(token) and byte_size(token) == 43 do
    hash = token_hash(token)

    Repo.exists?(
      from(s in Session,
        where: s.token_hash == ^hash and s.account_id == ^id and s.expires_at == ^expires
      )
    )
  end

  defp registered?(_), do: false
  defp token_hash(token), do: :crypto.hash(:sha256, token)

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
