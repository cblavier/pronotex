defmodule Pronotex.AuthTest do
  use ExUnit.Case, async: false
  alias Pronotex.{Auth, Repo}
  alias Pronotex.Auth.Session

  test "sessions store only token hashes and reject missing or unknown identifiers" do
    session = Auth.session()
    token = session["auth_session_id"]
    assert byte_size(token) == 43
    stored = Repo.get!(Session, :crypto.hash(:sha256, token))
    assert stored.account_id == "family"
    assert stored.expires_at == session["auth_expires_at"]
    assert Auth.valid?(session)
    refute Auth.valid?(Map.delete(session, "auth_session_id"))
    refute Auth.valid?(Map.put(session, "auth_session_id", String.duplicate("a", 43)))
    other = Auth.session("parent-1")
    refute Auth.valid?(Map.put(other, "auth_session_id", token))
    refute Auth.valid?(Map.update!(session, "auth_expires_at", &(&1 + 3600)))
  end

  test "revocation survives auth process restarts while other sessions remain valid" do
    revoked = Auth.session("family", true)
    active = Auth.session("family", true)
    assert :ok = Auth.revoke(revoked)
    assert :ok = Auth.revoke(revoked)
    assert :ok = Supervisor.terminate_child(Pronotex.Supervisor, Auth)
    assert {:ok, _} = Supervisor.restart_child(Pronotex.Supervisor, Auth)
    refute Auth.valid?(revoked)
    assert Auth.valid?(active)
  end

  test "creating sessions purges expired records without deleting active sessions" do
    active = Auth.session()
    expired_hash = :crypto.strong_rand_bytes(32)

    Repo.insert!(%Session{
      token_hash: expired_hash,
      account_id: "family",
      expires_at: Auth.now() - 1
    })

    Auth.session()
    assert Repo.get(Session, expired_hash) == nil
    assert Auth.valid?(active)
  end
end
