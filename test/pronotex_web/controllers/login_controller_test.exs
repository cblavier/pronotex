defmodule PronotexWeb.LoginControllerTest do
  use PronotexWeb.ConnCase, async: false

  setup do
    :sys.replace_state(Pronotex.Auth, fn _ -> %{failures: 0, retry_at: 0} end)
    on_exit(fn -> :sys.replace_state(Pronotex.Auth, fn _ -> %{failures: 0, retry_at: 0} end) end)
    :ok
  end

  test "private pages and both avatar paths require a session" do
    for path <- ["/", "/alice/devoirs", "/avatars/1", "/images/avatars/private.png"] do
      assert build_conn() |> get(path) |> redirected_to() == "/login"
    end

    assert build_conn() |> get("/login") |> html_response(200) =~ "Code PIN"
  end

  test "logout clears the session and disconnects its live pages" do
    conn = build_conn() |> post("/login", %{"pin" => "01234567"})
    socket_id = get_session(conn, "live_socket_id")
    PronotexWeb.Endpoint.subscribe(socket_id)
    conn = conn |> recycle() |> post("/logout", %{})
    assert redirected_to(conn) == "/login"
    assert get_session(conn) == %{}
    assert_receive %Phoenix.Socket.Broadcast{topic: ^socket_id, event: "disconnect"}
    assert conn |> recycle() |> get("/") |> redirected_to() == "/login"
  end

  test "missing or empty PIN leaves access open without an authentication timer" do
    original = Pronotex.Auth.pin()
    on_exit(fn -> Application.put_env(:pronotex, :pin_code, original) end)

    for value <- [nil, ""] do
      Application.put_env(:pronotex, :pin_code, value)
      assert Pronotex.Auth.valid?(%{})
      assert build_conn() |> get("/login") |> redirected_to() == "/"
      assert build_conn() |> post("/login", %{}) |> redirected_to() == "/"
      assert build_conn() |> get("/avatars/unknown") |> response(404) == ""
      socket = %Phoenix.LiveView.Socket{}
      assert {:cont, ^socket} = PronotexWeb.Auth.on_mount(:default, %{}, %{}, socket)
    end
  end

  test "login accepts leading zeroes and sets an absolute twelve hour expiry" do
    conn = build_conn() |> post("/login", %{"pin" => "01234567"})
    assert redirected_to(conn) == "/"

    assert get_session(conn, "auth_expires_at") in (Pronotex.Auth.now() + 43_199)..(Pronotex.Auth.now() +
                                                                                      43_200)

    assert Pronotex.Auth.valid?(get_session(conn))

    conn =
      build_conn()
      |> Plug.Test.init_test_session(
        Map.put(Pronotex.Auth.session(), "auth_expires_at", Pronotex.Auth.now())
      )

    assert conn |> get("/") |> redirected_to() == "/login"
  end

  test "three failures block even a correct PIN, and subsequent failures increase the delay" do
    for _ <- 1..2, do: assert({:invalid, 0} = Pronotex.Auth.attempt("11111111"))
    assert {:invalid, 60} = Pronotex.Auth.attempt("11111111")
    conn = build_conn() |> post("/login", %{"pin" => "01234567"})
    assert conn.status == 429
    assert [seconds] = get_resp_header(conn, "retry-after")
    assert String.to_integer(seconds) > 0
    assert :sys.get_state(Pronotex.Auth).failures == 3
    :sys.replace_state(Pronotex.Auth, &%{&1 | retry_at: System.monotonic_time(:second) - 1})
    assert {:invalid, 120} = Pronotex.Auth.attempt("11111111")
    :sys.replace_state(Pronotex.Auth, &%{&1 | retry_at: System.monotonic_time(:second) - 1})
    assert {:invalid, 180} = Pronotex.Auth.attempt("11111111")
    :sys.replace_state(Pronotex.Auth, &%{&1 | retry_at: System.monotonic_time(:second) - 1})
    assert :ok = Pronotex.Auth.attempt("01234567")
    assert {:invalid, 0} = Pronotex.Auth.attempt("11111111")
  end

  test "invalid or changed PIN invalidates existing sessions" do
    session = Pronotex.Auth.session()
    original = Pronotex.Auth.pin()
    on_exit(fn -> Application.put_env(:pronotex, :pin_code, original) end)
    Application.put_env(:pronotex, :pin_code, "invalid")
    refute Pronotex.Auth.valid?(session)
    assert :unconfigured = Pronotex.Auth.attempt("01234567")
    assert build_conn() |> get("/login") |> html_response(200) =~ "Accès indisponible"
    Application.put_env(:pronotex, :pin_code, "87654321")
    refute Pronotex.Auth.valid?(session)
  end
end
