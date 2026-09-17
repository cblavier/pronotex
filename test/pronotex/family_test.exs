defmodule Pronotex.FamilyTest do
  use ExUnit.Case, async: false
  alias Pronotex.Family

  setup do
    keys =
      for index <- [71, 72],
          field <- ~w(FIRST_NAME THEME AVATAR USERNAME PASSWORD),
          do: "PRONOTE_CHILD_#{index}_#{field}"

    original = Map.new(keys, &{&1, System.get_env(&1)})
    Enum.each(keys, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(original, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end)

    :ok
  end

  test "configuration follows the name rather than the API order" do
    a = %{id: "a", name: "TEST Camille", first_name: "Camille"}
    b = %{id: "b", name: "TEST Sacha", first_name: "Sacha"}
    System.put_env("PRONOTE_CHILD_71_FIRST_NAME", " camille ")
    System.put_env("PRONOTE_CHILD_71_THEME", "green")
    System.put_env("PRONOTE_CHILD_71_AVATAR", "/images/avatars/local.png")
    assert Family.prefix(a) == "PRONOTE_CHILD_71"
    assert Family.theme([a, b], a) == "green"
    assert Family.theme([b, a], a) == "green"
    assert Family.avatar(a) == "/images/avatars/local.png"
    assert Family.prefix(b) == nil
    assert Family.avatar(b) == nil
  end

  test "duplicate configurations disable association" do
    child = %{name: "TEST Camille", first_name: "Camille"}
    for i <- [71, 72], do: System.put_env("PRONOTE_CHILD_#{i}_FIRST_NAME", "Camille")
    assert Family.prefix(child) == nil
    assert Family.value(child, "USERNAME") == nil
  end

  test "defaults work for more than two children and reject unsafe avatars" do
    children = for i <- 1..3, do: %{id: i, name: "TEST Child#{i}", first_name: "Child#{i}"}
    assert Enum.map(children, &Family.theme(children, &1)) == ["blue", "green", "blue"]
    child = hd(children)
    System.put_env("PRONOTE_CHILD_71_FIRST_NAME", "Child1")

    for path <- ["https://example.com/a.png", "/images/avatars/../secret", "//example.com/a.png"] do
      System.put_env("PRONOTE_CHILD_71_AVATAR", path)
      assert Family.avatar(child) == nil
    end
  end
end
