defmodule PronotexWeb.AvatarControllerTest do
  use PronotexWeb.ConnCase, async: false

  setup do
    keys = ~w(PRONOTE_CHILD_91_FIRST_NAME PRONOTE_CHILD_91_AVATAR_BASE64 PRONOTE_CHILD_91_AVATAR)
    old = Map.new(keys, &{&1, System.get_env(&1)})
    Enum.each(keys, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(old, fn {k, v} -> if v, do: System.put_env(k, v), else: System.delete_env(k) end)
    end)

    :ok
  end

  test "serves encoded images without local files", %{conn: conn} do
    bytes =
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3ioAAAAASUVORK5CYII="
      )

    System.put_env("PRONOTE_CHILD_91_FIRST_NAME", "Camille")
    System.put_env("PRONOTE_CHILD_91_AVATAR_BASE64", Base.encode64(bytes))
    assert Pronotex.Family.avatar(%{name: "Camille"}) == "/avatars/91"
    conn = get(conn, "/avatars/91")
    assert response(conn, 200) == bytes
    assert get_resp_header(conn, "content-type") == ["image/png; charset=utf-8"]
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
  end

  test "missing, invalid and oversized images are not served", %{conn: conn} do
    for value <- ["", "invalid!", Base.encode64("<svg></svg>"), String.duplicate("A", 262_145)] do
      System.put_env("PRONOTE_CHILD_91_AVATAR_BASE64", value)
      assert response(get(conn, "/avatars/91"), 404) == ""
    end

    assert response(get(conn, "/avatars/not-an-index"), 404) == ""
  end

  test "invalid base64 falls back to the local avatar" do
    System.put_env("PRONOTE_CHILD_91_FIRST_NAME", "Camille")
    System.put_env("PRONOTE_CHILD_91_AVATAR_BASE64", "invalid")
    System.put_env("PRONOTE_CHILD_91_AVATAR", "/images/avatars/local.png")
    assert Pronotex.Family.avatar(%{name: "Camille"}) == "/images/avatars/local.png"
  end
end
