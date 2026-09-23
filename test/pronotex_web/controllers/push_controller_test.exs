defmodule PronotexWeb.PushControllerTest do
  use PronotexWeb.ConnCase, async: false
  alias Pronotex.{Push, Repo}
  alias Pronotex.Push.Subscription

  defp params do
    %{
      "endpoint" => "https://web.push.apple.com/controller-test",
      "keys" => %{
        "p256dh" => WebPush.Vapid.generate_keypair().public_key,
        "auth" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      }
    }
  end

  setup do
    Repo.delete_all(Subscription)
    :ok
  end

  test "configuration and mutations require authentication" do
    assert build_conn() |> get("/push/config") |> redirected_to() == "/login"
    assert build_conn() |> post("/push/subscription", params()) |> redirected_to() == "/login"
    assert build_conn() |> delete("/push/subscription") |> redirected_to() == "/login"
    assert Repo.all(Subscription) == []
  end

  test "subscribe, read status and disable using the signed device cookie", %{conn: conn} do
    assert conn |> get("/push/config") |> json_response(200) == %{
             "publicKey" => Push.public_key(),
             "enabled" => false
           }

    created = conn |> post("/push/subscription", params())
    assert json_response(created, 200) == %{"enabled" => true}
    assert [%{account_id: "family"}] = Repo.all(Subscription)

    assert created
           |> recycle()
           |> get("/push/config")
           |> json_response(200)
           |> Map.fetch!("enabled")

    disabled = created |> recycle() |> delete("/push/subscription")
    assert json_response(disabled, 200) == %{"enabled" => false}
    assert Repo.all(Subscription) == []
  end

  test "POST cannot select another account and rejects invalid input", %{conn: conn} do
    assert conn |> post("/push/subscription", %{}) |> json_response(422)
    conn |> post("/push/subscription", Map.put(params(), "account_id", "child-1"))
    assert [%{account_id: "family"}] = Repo.all(Subscription)
  end

  test "mutations enforce CSRF", %{conn: conn} do
    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      conn
      |> put_private(:plug_skip_csrf_protection, false)
      |> post("/push/subscription", params())
    end

    assert Repo.all(Subscription) == []
  end

  test "logout unregisters this device", %{conn: conn} do
    created = conn |> post("/push/subscription", params())
    assert [_] = Repo.all(Subscription)
    assert created |> recycle() |> post("/logout") |> redirected_to() == "/login"
    assert Repo.all(Subscription) == []
  end

  test "worker is public and does not cache private pages" do
    body = build_conn() |> get("/push-sw.js") |> response(200)
    assert body =~ "notificationclick"
    refute body =~ "caches.open"
    assert body =~ "target.origin === self.location.origin"
  end
end
