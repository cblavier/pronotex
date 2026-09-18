defmodule PronotexWeb.ManifestTest do
  use PronotexWeb.ConnCase, async: false

  test "production manifest is public and leaves the login session untouched" do
    body = File.read!("priv/static/manifest.webmanifest")
    # A real digest-shaped asset, independent of a prior production build.
    digest = :crypto.hash(:md5, body) |> Base.encode16(case: :lower)
    name = "manifest-#{digest}.webmanifest"
    path = Path.join("priv/static", name)

    unless File.exists?(path) do
      File.write!(path, body)
      on_exit(fn -> File.rm!(path) end)
    end

    login =
      build_conn() |> Plug.Conn.put_private(:plug_skip_csrf_protection, false) |> get("/login")

    token =
      login
      |> html_response(200)
      |> Floki.parse_document!()
      |> Floki.find("input[name=_csrf_token]")
      |> Floki.attribute("value")
      |> hd()

    for url <- ["/manifest.webmanifest", "/" <> name] do
      manifest = login |> recycle() |> get(url)
      assert response(manifest, 200) == body
      assert get_resp_header(manifest, "location") == []
      assert get_resp_header(manifest, "set-cookie") == []
    end

    manifest = login |> recycle() |> get("/" <> name)

    result =
      manifest
      |> recycle()
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)
      |> post("/login", %{"pin" => "01234567", "_csrf_token" => token})

    assert redirected_to(result) == "/"
    assert Pronotex.Auth.valid?(get_session(result))
  end
end
