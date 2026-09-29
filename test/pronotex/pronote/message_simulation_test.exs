defmodule Pronotex.Pronote.MessageSimulationTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias Pronotex.Pronote.Transport

  test "transport blocks message writes before touching HTTP or session state and logs exact JSON" do
    # Intentionally has no HTTP client, keys or session: even direct calls must be safe.
    transport = %Transport{order: 17}

    payload = %{
      "Signature" => %{"onglet" => 131, "membre" => %{"N" => "alice", "G" => 4}},
      "data" => %{
        "objet" => "Question : \"devoirs\"",
        "contenu" => "Bonjour,\nUne question pour demain.",
        "listeDestinataires" => [%{"N" => "teacher", "G" => 3, "L" => "Mme Martin"}]
      }
    }

    log =
      capture_log(fn ->
        assert {%{simulated: true}, ^transport} =
                 Transport.call(transport, "SaisieMessage", payload)
      end)

    assert log =~ Jason.encode!(%{"function" => "SaisieMessage", "payload" => payload})
  end

  test "other message-writing commands are blocked too" do
    transport = %Transport{}

    capture_log(fn ->
      assert {%{simulated: true}, ^transport} =
               Transport.call(transport, "SaisieMessage", %{
                 "data" => %{"commande" => "repondre", "contenu" => "Bonjour"}
               })
    end)
  end
end
