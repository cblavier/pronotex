defmodule PronotexWeb.CSRFProtectionTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test
  import ExUnit.CaptureLog

  alias PronotexWeb.CSRFProtection

  test "missing cookie and tokens are rejected with safe diagnostics" do
    conn = conn(:post, "/login", %{"pin" => "sensitive-pin"}) |> init_test_session(%{})

    log =
      capture_log(fn ->
        rejected = CSRFProtection.call(conn, CSRFProtection.init([]))
        assert rejected.status == 303
        assert rejected.halted
        assert get_resp_header(rejected, "location") == ["/login?session_expired=1"]
        assert get_session(rejected) == %{}
      end)

    assert log =~ "session_cookie_present=false"
    assert log =~ "session_csrf_present=false"
    assert log =~ "form_csrf_present=false"
    refute log =~ "sensitive-pin"
  end

  test "valid CSRF pair passes and mismatched tokens still fail" do
    token = Plug.CSRFProtection.get_csrf_token()
    state = Plug.CSRFProtection.dump_state()
    Plug.CSRFProtection.delete_csrf_token()

    conn =
      conn(:post, "/logout", %{"_csrf_token" => token})
      |> init_test_session(%{"_csrf_token" => state})

    assert CSRFProtection.call(conn, CSRFProtection.init([])).halted == false
    Plug.CSRFProtection.delete_csrf_token()

    bad_conn = %{conn | body_params: %{"_csrf_token" => "sensitive-invalid-token"}}

    log =
      capture_log(fn ->
        assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
          CSRFProtection.call(bad_conn, CSRFProtection.init([]))
        end
      end)

    assert log =~ "session_csrf_present=true"
    assert log =~ "form_csrf_present=true"
    refute log =~ "sensitive-invalid-token"
    assert get_session(conn, "_csrf_token") == state
  end
end
