defmodule PronotexWeb.ManifestTest do
  use PronotexWeb.ConnCase, async: false

  test "installation page declares Apple standalone mode and serves matching launch images" do
    document = build_conn() |> get("/login") |> html_response(200) |> Floki.parse_document!()

    assert Floki.find(document, ~s(meta[name="apple-mobile-web-app-capable"]))
           |> Floki.attribute("content") == ["yes"]

    links = Floki.find(document, ~s(link[rel="apple-touch-startup-image"]))
    assert links != []

    for link <- links do
      [url] = Floki.attribute(link, "href")
      [media] = Floki.attribute(link, "media")

      [_, width, height, ratio, orientation] =
        Regex.run(
          ~r/device-width: (\d+)px.*device-height: (\d+)px.*pixel-ratio: (\d+).*orientation: (portrait|landscape)/,
          media
        )

      width = String.to_integer(width) * String.to_integer(ratio)
      height = String.to_integer(height) * String.to_integer(ratio)
      expected = if orientation == "portrait", do: {width, height}, else: {height, width}
      image = build_conn() |> get(url)
      assert get_resp_header(image, "content-type") == ["image/png"]
      assert get_resp_header(image, "location") == []

      assert <<137, "PNG\r\n", 26, "\n", 13::32, "IHDR", w::32, h::32, _::binary>> =
               response(image, 200)

      assert {w, h} == expected
    end
  end

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
      |> post("/login", %{"account" => "family", "pin" => "01234567", "_csrf_token" => token})

    assert redirected_to(result) == "/"
    assert Pronotex.Auth.valid?(get_session(result))
  end
end
