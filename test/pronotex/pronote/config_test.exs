defmodule Pronotex.Pronote.ConfigTest do
  use ExUnit.Case, async: false
  alias Pronotex.Pronote.{Config, Error}

  test "requires credentials and HTTPS parent URL, hides passwords on inspection" do
    config = %Config{
      url: "https://school.test/pronote/parent.html",
      username: "parent",
      password: "secret"
    }

    assert {:ok, ^config} = Config.validate(config)
    refute inspect(config) =~ "secret"

    assert {:error, %Error{reason: :missing_credentials}} =
             Config.validate(%{config | password: ""})

    for url <- [
          "http://school.test/pronote/parent.html",
          "https://school.test/eleve.html",
          "https://a:b@school.test/pronote/parent.html"
        ] do
      assert {:error, %Error{reason: :invalid_url}} = Config.validate(%{config | url: url})
    end
  end

  test "student credentials are optional and isolated by child" do
    keys =
      ~w(PRONOTE_CHILD_1_FIRST_NAME PRONOTE_CHILD_2_FIRST_NAME PRONOTE_URL PRONOTE_CHILD_1_USERNAME PRONOTE_CHILD_1_PASSWORD PRONOTE_CHILD_2_USERNAME PRONOTE_CHILD_2_PASSWORD)

    original = Map.new(keys, &{&1, System.get_env(&1)})

    on_exit(fn ->
      Enum.each(original, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end)

    Enum.each(keys, &System.delete_env/1)
    System.put_env("PRONOTE_URL", "https://school.test/pronote/")
    System.put_env("PRONOTE_CHILD_1_FIRST_NAME", "Alice")
    System.put_env("PRONOTE_CHILD_2_FIRST_NAME", "Basile")
    alice = %{name: "DUPONT Alice", first_name: nil}
    basile = %{name: "DUPONT Basile", first_name: "Basile"}
    refute Config.student_configured?(alice)
    System.put_env("PRONOTE_CHILD_1_USERNAME", "alice-test")
    refute Config.student_configured?(alice)
    System.put_env("PRONOTE_CHILD_1_PASSWORD", "secret-test")
    assert Config.student_configured?(alice)
    refute Config.student_configured?(basile)
    assert {:ok, config} = Config.student_from_env(alice)
    assert config.space == 3
    assert String.ends_with?(config.url, "/eleve.html")
    refute inspect(config) =~ "secret-test"
  end
end
