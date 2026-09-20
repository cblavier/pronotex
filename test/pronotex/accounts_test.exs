defmodule Pronotex.AccountsTest do
  use ExUnit.Case, async: false
  alias Pronotex.{Accounts, Auth}
  alias Pronotex.Pronote.{Config, Session}

  setup do
    original = Application.fetch_env!(:pronotex, :accounts)

    env =
      System.get_env()
      |> Enum.filter(fn {key, _} -> String.starts_with?(key, "PRONOTE_") end)
      |> Map.new()

    Enum.each(Map.keys(env), &System.delete_env/1)
    Application.delete_env(:pronotex, :accounts)

    on_exit(fn ->
      System.get_env()
      |> Map.keys()
      |> Enum.filter(&String.starts_with?(&1, "PRONOTE_"))
      |> Enum.each(&System.delete_env/1)

      System.put_env(env)
      Application.put_env(:pronotex, :accounts, original)
    end)

    :ok
  end

  defp profile(prefix, name \\ nil, pin \\ "01234567") do
    System.put_env(prefix <> "_USERNAME", "test-" <> prefix)
    System.put_env(prefix <> "_PASSWORD", "test-secret")
    System.put_env(prefix <> "_PIN_CODE", pin)
    if name, do: System.put_env(prefix <> "_FIRST_NAME", name)
  end

  test "enumerates all numbered profiles in order without revealing credentials" do
    profile("PRONOTE_FAMILY")
    profile("PRONOTE_PARENT_2", "Dominique")
    profile("PRONOTE_PARENT_1", "Camille")
    profile("PRONOTE_CHILD_10", "Basile")
    profile("PRONOTE_CHILD_2", "Alice")

    assert Enum.map(Accounts.all(), & &1.id) == [
             "family",
             "child-2",
             "child-10",
             "parent-1",
             "parent-2"
           ]

    assert Enum.map(Accounts.all(), & &1.role) == [:family, :child, :child, :parent, :parent]

    assert Enum.map(Accounts.all(), & &1.label) == [
             "Famille",
             "Alice",
             "Basile",
             "Camille",
             "Dominique"
           ]

    refute inspect(Accounts.all()) =~ "test-secret"
    refute inspect(Accounts.all()) =~ "01234567"
    refute inspect(Accounts.all()) =~ "username"
    System.delete_env("PRONOTE_PARENT_1_PASSWORD")
    System.delete_env("PRONOTE_CHILD_2_PIN_CODE")
    System.delete_env("PRONOTE_CHILD_10_FIRST_NAME")
    assert Enum.map(Accounts.all(), & &1.id) == ["family", "parent-2"]
  end

  test "base URL produces the correct space for each profile and rejects old URLs" do
    profile("PRONOTE_FAMILY")
    profile("PRONOTE_CHILD_1", "Alice")
    profile("PRONOTE_PARENT_1", "Camille")

    for base <- ["https://school.test/pronote", "https://school.test/pronote/"] do
      System.put_env("PRONOTE_URL", base)

      for {id, page, space} <- [
            {"family", "parent", 2},
            {"parent-1", "parent", 2},
            {"child-1", "eleve", 3}
          ] do
        assert {:ok, config} = Config.from_account(id)
        assert config.url == "https://school.test/pronote/#{page}.html"
        assert config.space == space
      end
    end

    for url <- [
          "http://school.test/pronote",
          "https://school.test/pronote/parent.html",
          "https://school.test/pronote/eleve.html",
          "https://school.test/pronote/parent.html/",
          "https://school.test/pronote?secret=1"
        ] do
      System.put_env("PRONOTE_URL", url)
      assert {:error, %{reason: :invalid_url}} = Config.from_account("family")
    end
  end

  test "removing a profile or changing its credentials revokes its session" do
    profile("PRONOTE_FAMILY")
    session = Auth.session()
    assert Auth.valid?(session)
    System.put_env("PRONOTE_FAMILY_PASSWORD", "replacement")
    refute Auth.valid?(session)
    session = Auth.session()
    System.delete_env("PRONOTE_FAMILY_PIN_CODE")
    refute Auth.valid?(session)
  end

  test "each profile owns a distinct serialized PRONOTE process" do
    profile("PRONOTE_FAMILY")
    profile("PRONOTE_PARENT_1", "Camille")
    profile("PRONOTE_CHILD_1", "Alice")
    processes = Enum.map(["family", "parent-1", "child-1"], &Session.for_account/1)

    on_exit(fn ->
      Enum.each(processes, &DynamicSupervisor.terminate_child(Pronotex.Pronote.Supervisor, &1))
    end)

    assert Enum.uniq(processes) == processes
    assert hd(processes) == Session.for_account("family")

    for {pid, id} <- Enum.zip(processes, ["family", "parent-1", "child-1"]) do
      assert :sys.get_state(pid).options[:account] == id
      assert :sys.get_state(pid).client == nil
    end

    assert_raise Pronotex.Pronote.Error, fn -> Session.for_account("unconfigured") end
  end
end
