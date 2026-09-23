defmodule PronotexWeb.LoginControllerTest do
  use PronotexWeb.ConnCase, async: false

  setup do
    :sys.replace_state(Pronotex.Auth, fn _ -> %{} end)
    on_exit(fn -> :sys.replace_state(Pronotex.Auth, fn _ -> %{} end) end)
    :ok
  end

  test "notes destination survives the login form and authentication" do
    target = "/edgar/notes?period=semester1"
    redirected = build_conn() |> get(target)
    login_url = redirected_to(redirected)
    assert login_url == PronotexWeb.NotesDestination.login_url(target)
    form = redirected |> recycle() |> get(login_url) |> html_response(200)
    assert form =~ ~s(name="return_to")
    assert form =~ target

    success =
      build_conn()
      |> post("/login", %{"account" => "family", "pin" => "01234567", "return_to" => target})

    assert redirected_to(success) == target
  end

  test "post-login destinations cannot redirect outside notes pages" do
    for target <- [
          "https://evil.test/a/notes",
          "//evil.test/a/notes",
          "/%2Fbad/notes",
          "/a/../notes",
          "/a/notes#bad",
          "/a/messages"
        ] do
      assert PronotexWeb.NotesDestination.validate(target) == nil
    end
  end

  test "private pages and both avatar paths require a session" do
    for path <- ["/", "/alice/devoirs", "/avatars/1", "/images/avatars/private.png"] do
      assert build_conn() |> get(path) |> redirected_to() == "/login"
    end

    assert build_conn() |> get("/login") |> html_response(200) =~ "Code PIN"
  end

  test "a protected request in another tab does not invalidate an open login form" do
    for path <- ["/", "/avatars/1", "/images/avatars/private.png"] do
      login = build_conn() |> put_private(:plug_skip_csrf_protection, false) |> get("/login")

      token =
        login
        |> html_response(200)
        |> Floki.parse_document!()
        |> Floki.find("input[name=_csrf_token]")
        |> Floki.attribute("value")
        |> hd()

      redirected =
        login |> recycle() |> put_private(:plug_skip_csrf_protection, false) |> get(path)

      assert redirected_to(redirected) == "/login"
      assert get_resp_header(redirected, "set-cookie") == []

      success =
        redirected
        |> recycle()
        |> put_private(:plug_skip_csrf_protection, false)
        |> post("/login", %{"account" => "family", "pin" => "01234567", "_csrf_token" => token})

      assert redirected_to(success) == "/"
      assert Pronotex.Auth.valid?(get_session(success))
    end
  end

  test "stale login form renews the session without checking the PIN, then accepts a fresh form" do
    conn =
      build_conn()
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)
      |> get("/login")

    rejected =
      ExUnit.CaptureLog.capture_log(fn ->
        rejected =
          conn
          |> recycle()
          |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)
          |> post("/login", %{
            "account" => "family",
            "pin" => "01234567",
            "_csrf_token" => "stale"
          })

        assert redirected_to(rejected, 303) == "/login?session_expired=1"
        refute Pronotex.Auth.valid?(get_session(rejected))
        assert :sys.get_state(Pronotex.Auth) == %{}

        fresh =
          rejected
          |> recycle()
          |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)
          |> get("/login?session_expired=1")

        html = html_response(fresh, 200)
        assert html =~ "Veuillez saisir votre code à nouveau"

        token =
          html
          |> Floki.parse_document!()
          |> Floki.find("input[name=_csrf_token]")
          |> Floki.attribute("value")
          |> hd()

        success =
          fresh
          |> recycle()
          |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)
          |> post("/login", %{"account" => "family", "pin" => "01234567", "_csrf_token" => token})

        assert redirected_to(success) == "/"
        assert Pronotex.Auth.valid?(get_session(success))
      end)

    assert rejected =~ "CSRF rejected:"
  end

  test "logout clears the session and disconnects its live pages" do
    conn = build_conn() |> post("/login", %{"account" => "family", "pin" => "01234567"})
    socket_id = get_session(conn, "live_socket_id")
    PronotexWeb.Endpoint.subscribe(socket_id)
    conn = conn |> recycle() |> post("/logout", %{})
    assert redirected_to(conn) == "/login"
    assert get_session(conn) == %{}
    assert_receive %Phoenix.Socket.Broadcast{topic: ^socket_id, event: "disconnect"}
    assert conn |> recycle() |> get("/") |> redirected_to() == "/login"
  end

  test "no configured profile keeps private pages closed" do
    original = Application.fetch_env!(:pronotex, :accounts)
    on_exit(fn -> Application.put_env(:pronotex, :accounts, original) end)
    Application.put_env(:pronotex, :accounts, [])
    refute Pronotex.Auth.valid?(%{})
    assert build_conn() |> get("/") |> redirected_to() == "/login"
    assert build_conn() |> get("/login") |> html_response(200) =~ "Accès indisponible"
    assert :unconfigured = Pronotex.Auth.attempt("family", "01234567")
  end

  test "login accepts leading zeroes and sets an absolute one hour expiry" do
    conn = build_conn() |> post("/login", %{"account" => "family", "pin" => "01234567"})
    assert redirected_to(conn) == "/"

    assert get_session(conn, "auth_expires_at") in (Pronotex.Auth.now() + 3_599)..(Pronotex.Auth.now() +
                                                                                     3_600)

    assert Pronotex.Auth.valid?(get_session(conn))

    conn =
      build_conn()
      |> Plug.Test.init_test_session(
        Map.put(Pronotex.Auth.session(), "auth_expires_at", Pronotex.Auth.now())
      )

    assert conn |> get("/") |> redirected_to() == "/login"
  end

  test "login cookie persists for one hours and restores authentication in a fresh connection" do
    conn = build_conn() |> post("/login", %{"account" => "family", "pin" => "01234567"})
    cookie = conn.resp_cookies["_pronotex_key"]
    assert cookie.max_age == 3_600
    assert Enum.any?(get_resp_header(conn, "set-cookie"), &String.contains?(&1, "HttpOnly"))
    expires_at = get_session(conn, "auth_expires_at")

    restored =
      build_conn()
      |> put_req_cookie("_pronotex_key", cookie.value)
      |> get("/login")

    assert redirected_to(restored) == "/"
    assert get_session(restored, "auth_expires_at") == expires_at
    assert Pronotex.Auth.valid?(get_session(restored))

    logged_out = restored |> recycle() |> post("/logout", %{})
    assert logged_out.resp_cookies["_pronotex_key"].max_age == 0
  end

  test "three failures block even a correct PIN, and subsequent failures increase the delay" do
    for _ <- 1..2, do: assert({:invalid, 0} = Pronotex.Auth.attempt("family", "11111111"))
    assert {:invalid, 60} = Pronotex.Auth.attempt("family", "11111111")
    conn = build_conn() |> post("/login", %{"account" => "family", "pin" => "01234567"})
    assert conn.status == 429
    assert [seconds] = get_resp_header(conn, "retry-after")
    assert String.to_integer(seconds) > 0
    assert :sys.get_state(Pronotex.Auth)["family"].failures == 3

    :sys.replace_state(
      Pronotex.Auth,
      &put_in(&1, ["family", :retry_at], System.monotonic_time(:second) - 1)
    )

    assert {:invalid, 120} = Pronotex.Auth.attempt("family", "11111111")

    :sys.replace_state(
      Pronotex.Auth,
      &put_in(&1, ["family", :retry_at], System.monotonic_time(:second) - 1)
    )

    assert {:invalid, 180} = Pronotex.Auth.attempt("family", "11111111")

    :sys.replace_state(
      Pronotex.Auth,
      &put_in(&1, ["family", :retry_at], System.monotonic_time(:second) - 1)
    )

    assert :ok = Pronotex.Auth.attempt("family", "01234567")
    assert {:invalid, 0} = Pronotex.Auth.attempt("family", "11111111")
  end

  test "invalid, changed or removed profiles invalidate existing sessions" do
    session = Pronotex.Auth.session()
    original = Application.fetch_env!(:pronotex, :accounts)
    on_exit(fn -> Application.put_env(:pronotex, :accounts, original) end)

    for pin <- ["invalid", "87654321"] do
      Application.put_env(:pronotex, :accounts, Enum.map(original, &Map.put(&1, :pin, pin)))
      refute Pronotex.Auth.valid?(session)
    end

    Application.put_env(:pronotex, :accounts, [])
    refute Pronotex.Auth.valid?(session)
  end

  test "login exposes only profile names and remembering is off by default" do
    html = build_conn() |> get("/login") |> html_response(200)
    document = Floki.parse_document!(html)

    assert Floki.find(document, "#login-account-picker .dropdown-option") |> Floki.text() =~
             "Famille"

    assert html =~ "Alice"
    assert html =~ "Camille"
    assert Floki.find(document, "input[name=remember][checked]") == []
    refute html =~ "test-password"
    refute html =~ "test-parent"
    refute html =~ "01234567"
  end

  test "PIN belongs to the selected account and throttling is independent" do
    for _ <- 1..3, do: Pronotex.Auth.attempt("child-1", "01234567")
    assert {:wait, _} = Pronotex.Auth.attempt("child-1", "12345678")
    assert :ok = Pronotex.Auth.attempt("family", "01234567")
    assert :ok = Pronotex.Auth.attempt("parent-1", "23456789")
    assert :unconfigured = Pronotex.Auth.attempt("unknown", "01234567")
    result = build_conn() |> post("/login", %{"account" => "parent-1", "pin" => "23456789"})
    assert get_session(result, "auth_account") == "parent-1"
  end

  test "remembered login persists thirty days without extending absolute expiry" do
    result =
      build_conn()
      |> post("/login", %{"account" => "child-1", "pin" => "12345678", "remember" => "true"})

    assert redirected_to(result) == "/"
    expiry = get_session(result, "auth_expires_at")
    assert expiry in (Pronotex.Auth.now() + 2_591_999)..(Pronotex.Auth.now() + 2_592_000)
    cookie = result.resp_cookies["_pronotex_key"]
    assert cookie.max_age in 2_591_999..2_592_000
    restored = build_conn() |> put_req_cookie("_pronotex_key", cookie.value) |> get("/login")
    assert redirected_to(restored) == "/"
    assert get_session(restored, "auth_expires_at") == expiry
    assert get_session(restored, "auth_account") == "child-1"
  end
end
