defmodule PronotexWeb.DeploymentControllerTest do
  use PronotexWeb.ConnCase, async: true

  test "the public deployment version matches the page and cannot be cached" do
    conn = build_conn() |> get("/app-version")
    assert %{"version" => version} = json_response(conn, 200)
    assert version == PronotexWeb.DeploymentController.version()
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    html = build_conn() |> get("/login") |> html_response(200)

    assert Floki.parse_document!(html) |> Floki.attribute("meta[name=app-version]", "content") ==
             [version]

    assert get_resp_header(build_conn() |> get("/login"), "cache-control") == [
             "private, no-store"
           ]
  end
end
