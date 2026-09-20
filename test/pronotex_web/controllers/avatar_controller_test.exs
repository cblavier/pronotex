defmodule PronotexWeb.AvatarControllerTest do
  use PronotexWeb.ConnCase, async: false

  defmodule API do
    def children, do: {:ok, [%{name: "Camille"}]}
  end

  setup do
    api = Application.get_env(:pronotex, :pronote_client)
    Application.put_env(:pronotex, :pronote_client, API)

    on_exit(fn ->
      if api,
        do: Application.put_env(:pronotex, :pronote_client, api),
        else: Application.delete_env(:pronotex, :pronote_client)
    end)

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

  test "a child cannot fetch another child's avatar", %{conn: conn} do
    bytes = <<137, 80, 78, 71, 13, 10, 26, 10>>
    System.put_env("PRONOTE_CHILD_91_FIRST_NAME", "Other child")
    System.put_env("PRONOTE_CHILD_91_AVATAR_BASE64", Base.encode64(bytes))
    conn = conn |> Plug.Test.init_test_session(Pronotex.Auth.session("child-1"))
    assert response(get(conn, "/avatars/91"), 404) == ""
  end

  test "invalid base64 falls back to the local avatar" do
    System.put_env("PRONOTE_CHILD_91_FIRST_NAME", "Camille")
    System.put_env("PRONOTE_CHILD_91_AVATAR_BASE64", "invalid")
    System.put_env("PRONOTE_CHILD_91_AVATAR", "/images/avatars/local.png")
    assert Pronotex.Family.avatar(%{name: "Camille"}) == "/images/avatars/local.png"
  end
end
