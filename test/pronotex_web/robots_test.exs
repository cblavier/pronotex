defmodule PronotexWeb.RobotsTest do
  use PronotexWeb.ConnCase, async: true

  test "indexing directives cover public pages, redirects and static files" do
    for path <- ["/login", "/", "/robots.txt", "/manifest.webmanifest"] do
      conn = get(build_conn(), path)

      assert get_resp_header(conn, "x-robots-tag") == [
               "noindex, nofollow, noimageindex, nosnippet"
             ]
    end
  end

  test "robots.txt is public and disallows all crawlers" do
    conn = get(build_conn(), "/robots.txt")
    assert conn.status == 200
    assert conn.resp_body =~ "User-agent: *\nDisallow: /"
  end

  test "login includes the robots meta tag" do
    html = build_conn() |> get("/login") |> html_response(200)
    assert html =~ ~s(name="robots" content="noindex, nofollow, noimageindex, nosnippet")
  end
end
