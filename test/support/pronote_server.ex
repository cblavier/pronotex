defmodule Pronotex.Test.PronoteServer do
  @moduledoc false
  import ExUnit.Assertions

  # Independent server emulator: validates request order, challenge, crypto,
  # cookies and parent signatures; no production codec functions are reused.
  def initial(options) do
    %{
      options: options,
      calls: [],
      homework_status: %{},
      discussion_read: false,
      logins: 0,
      expired?: false,
      order: 1,
      iv: <<0::128>>,
      key: :crypto.hash(:md5, ""),
      cookie: false
    }
  end

  def handle(conn, agent) do
    if conn.method == "GET" do
      Agent.update(agent, fn state ->
        %{
          state
          | logins: state.logins + 1,
            order: 1,
            iv: <<0::128>>,
            key: :crypto.hash(:md5, ""),
            cookie: false
        }
      end)

      options = Agent.get(agent, & &1.options)

      html =
        "<body onload=\"Start ({'h':12345,'a':#{options[:space] || 2},'CrA':#{options[:encrypted]},'CoA':#{options[:compressed]}})\"></body>"

      conn |> Plug.Conn.put_resp_content_type("text/html") |> Plug.Conn.send_resp(200, html)
    else
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)

      {response, cookie?, error?} =
        Agent.get_and_update(agent, fn state -> respond(request, conn, state) end)

      conn =
        if cookie?,
          do:
            Plug.Conn.put_resp_header(
              conn,
              "set-cookie",
              "session=test-cookie; Secure; HttpOnly; Path=/pronote"
            ),
          else: conn

      if error?,
        do: Req.Test.json(conn, response),
        else: Req.Test.json(conn, %{"dataSec" => response})
    end
  end

  defp respond(request, conn, state) do
    assert request["session"] == 12345
    assert decrypt(request["no"], state.key, state.iv) == Integer.to_string(state.order)

    assert conn.request_path ==
             "/pronote/appelfonction/#{state.options[:space] || 2}/12345/#{request["no"]}"

    if state.cookie,
      do: assert(Plug.Conn.get_req_header(conn, "cookie") == ["session=test-cookie"])

    payload = decode(request["dataSec"], state)
    function = request["id"]
    state = %{state | calls: state.calls ++ [{function, payload}], order: state.order + 2}

    cond do
      function in ["SaisieTAFFaitEleve", "SaisieMessage"] and state.options[:write_error] ->
        {{%{"Erreur" => %{"G" => state.options[:write_error]}}, false, true}, state}

      function == "PageEmploiDuTemps" and state.options[:expire] in [true, :always] and
          (not state.expired? or state.options[:expire] == :always) ->
        {{%{"Erreur" => %{"G" => 10, "Titre" => "expired"}}, false, true},
         %{state | expired?: true}}

      true ->
        {data, state, next_key, cookie?} = data(function, payload, state)

        data =
          if function == "ParametresUtilisateur" and state.options[:space] == 3 do
            resource = hd(data["ressource"]["listeRessources"])

            resource =
              if state.options[:wrong_student],
                do: Map.put(resource, "L", "Autre Enfant"),
                else: resource

            Map.put(data, "ressource", resource)
          else
            data
          end

        encoded = encode(%{"data" => data}, state)

        {{encoded, cookie?, false},
         %{state | key: next_key || state.key, cookie: state.cookie or cookie?}}
    end
  end

  defp data("FonctionParametres", payload, state) do
    iv = :crypto.hash(:md5, Base.decode64!(payload["data"]["Uuid"]))

    general = %{
      "PremierLundi" => %{"V" => "31/08/2026"},
      "DerniereDate" => %{"V" => "04/07/2027"},
      "ListeHeuresFin" => %{
        "V" => [
          %{"G" => 0, "L" => "08h55"},
          %{"G" => 1, "L" => "09h55"},
          %{"G" => 2, "L" => "10h55"}
        ]
      }
    }

    {%{"General" => general, "identifiantNav" => "browser-id"}, %{state | iv: iv}, nil, false}
  end

  defp data("Identification", payload, state) do
    assert payload["data"]["identifiant"] == "Parent"
    assert payload["data"]["pourENT"] == false

    {%{
       "modeCompLog" => 1,
       "modeCompMdp" => 0,
       "alea" => "salt",
       "challenge" => "challenge-test"
     }, state, nil, false}
  end

  defp data("Authentification", payload, state) do
    hash = :crypto.hash(:sha256, "saltPaSsWord-TEST") |> Base.encode16()
    key = :crypto.hash(:md5, "parent" <> hash)
    assert decrypt(payload["data"]["challenge"], key, state.iv) == "challenge-test"
    next_key = :crypto.hash(:md5, <<1, 2, 3, 4, 5>>)

    result =
      cond do
        state.options[:bad_credentials] ->
          %{}

        state.options[:mfa] ->
          %{"cle" => encrypt("1,2,3,4,5", key, state.iv), "actionsDoubleAuth" => %{"V" => "[3]"}}

        true ->
          %{"cle" => encrypt("1,2,3,4,5", key, state.iv)}
      end

    {result, state, next_key, true}
  end

  defp data("ParametresUtilisateur", _, state) do
    tabs =
      if state.options[:forbidden],
        do: [7],
        else: [
          %{
            "G" => 7,
            "Onglets" => [
              %{"G" => 16},
              %{"G" => 88},
              %{"G" => 10},
              %{"G" => 198},
              %{"G" => 9},
              %{"G" => 131}
            ]
          }
        ]

    {%{
       "ressource" => %{
         "listeRessources" => [
           %{
             "N" => "child-a",
             "L" => "Enfant A",
             "G" => 4,
             "listeOngletsPourPeriodes" => %{
               "V" => [
                 %{
                   "G" => 198,
                   "listePeriodes" => %{
                     "V" => [
                       %{"N" => "s1", "L" => "Semestre 1"},
                       %{"N" => "s2", "L" => "Semestre 2"}
                     ]
                   },
                   "periodeParDefaut" => %{"V" => %{"N" => "s1"}}
                 }
               ]
             }
           },
           %{
             "N" => "child-b",
             "L" => "Enfant B",
             "G" => 4,
             "listeOngletsPourPeriodes" => %{
               "V" => [
                 %{
                   "G" => 198,
                   "listePeriodes" => %{
                     "V" => [
                       %{"N" => "s1", "L" => "Semestre 1"},
                       %{"N" => "s2", "L" => "Semestre 2"}
                     ]
                   },
                   "periodeParDefaut" => %{"V" => %{"N" => "s1"}}
                 }
               ]
             }
           }
         ]
       },
       "listeOnglets" => tabs
     }, state, nil, false}
  end

  defp data("PageEmploiDuTemps", payload, state) do
    id = if state.options[:space] == 3, do: "child-a", else: payload["Signature"]["membre"]["N"]

    expected =
      if state.options[:space] == 3,
        do: %{"onglet" => 16},
        else: %{"onglet" => 16, "membre" => %{"N" => id, "G" => 4}}

    assert payload["Signature"] == expected
    assert payload["data"]["ressource"]["N"] == id
    assert payload["data"]["Ressource"]["N"] == id
    week = payload["data"]["numeroSemaine"]
    assert payload["data"]["NumeroSemaine"] == week
    date = Date.add(~D[2026-08-31], (week - 1) * 7)
    date_string = Calendar.strftime(date, "%d/%m/%Y")

    lesson = %{
      "N" => "lesson-#{week}",
      "DateDuCours" => %{"V" => date_string <> " 08:00:00"},
      "place" => 0,
      "duree" => 1,
      "estAnnule" => true,
      "Statut" => "Cours annulé",
      "ListeContenus" => %{
        "V" => [
          %{"G" => 16, "L" => "Maths #{id}"},
          %{"G" => 3, "L" => "Professeur"},
          %{"G" => 17, "L" => "Salle 12"}
        ]
      }
    }

    {%{"ListeCours" => [lesson]}, state, nil, false}
  end

  defp data("PageCahierDeTexte", payload, state) do
    id = if state.options[:space] == 3, do: "child-a", else: payload["Signature"]["membre"]["N"]

    expected =
      if state.options[:space] == 3,
        do: %{"onglet" => 88},
        else: %{"onglet" => 88, "membre" => %{"N" => id, "G" => 4}}

    assert payload["Signature"] == expected
    assert payload["data"]["domaine"] == %{"_T" => 8, "V" => "[3..4]"}

    tasks =
      for {date, done, suffix} <- [
            {"14/09/2026", false, "early"},
            {"17/09/2026", true, "due"},
            {"25/09/2026", false, "late"}
          ] do
        %{
          "N" => "hw-#{suffix}",
          "Matiere" => %{"V" => %{"L" => "Français #{id}"}},
          "PourLe" => %{"V" => date},
          "TAFFait" => Map.get(state.homework_status, {id, "hw-#{suffix}"}, done),
          "descriptif" => %{
            "V" => "<p>Lire <b>le chapitre</b> &amp; réviser.</p><script>alert(1)</script>"
          }
        }
      end

    {%{"ListeTravauxAFaire" => %{"V" => tasks}}, state, nil, false}
  end

  defp data("SaisieTAFFaitEleve", payload, state) do
    assert state.options[:space] == 3
    id = if state.options[:space] == 3, do: "child-a", else: payload["Signature"]["membre"]["N"]

    expected =
      if state.options[:space] == 3,
        do: %{"onglet" => 88},
        else: %{"onglet" => 88, "membre" => %{"N" => id, "G" => 4}}

    assert payload["Signature"] == expected
    [%{"N" => task, "TAFFait" => done}] = payload["data"]["listeTAF"]
    assert is_boolean(done)

    state =
      if state.options[:ignore_write],
        do: state,
        else: %{state | homework_status: Map.put(state.homework_status, {id, task}, done)}

    {%{}, state, nil, false}
  end

  defp data("PageMenus", payload, state) do
    id = if state.options[:space] == 3, do: "child-a", else: payload["Signature"]["membre"]["N"]

    expected =
      if state.options[:space] == 3,
        do: %{"onglet" => 10},
        else: %{"onglet" => 10, "membre" => %{"N" => id, "G" => 4}}

    assert payload["Signature"] == expected
    assert payload["data"]["date"]["_T"] == 7
    date = payload["data"]["date"]["V"] |> String.split(" ") |> hd()

    meal = %{
      "N" => "lunch",
      "G" => 0,
      "ListePlats" => %{
        "V" => [
          %{"G" => 1, "ListeAliments" => %{"V" => [%{"L" => "Gratin"}]}},
          %{"G" => 4, "ListeAliments" => %{"V" => [%{"L" => "Pomme"}]}}
        ]
      }
    }

    {%{"ListeJours" => %{"V" => [%{"Date" => %{"V" => date}, "ListeRepas" => %{"V" => [meal]}}]}},
     state, nil, false}
  end

  defp data("DernieresNotes", payload, state) do
    id = if state.options[:space] == 3, do: "child-a", else: payload["Signature"]["membre"]["N"]

    expected =
      if state.options[:space] == 3,
        do: %{"onglet" => 198},
        else: %{"onglet" => 198, "membre" => %{"N" => id, "G" => 4}}

    assert payload["Signature"] == expected
    period = payload["data"]["Periode"]["N"]
    assert period in ["s1", "s2"]

    data = %{
      "moyGenerale" => %{"V" => "14,25"},
      "baremeMoyGenerale" => %{"V" => "20"},
      "listeDevoirs" => %{
        "V" => [
          %{
            "N" => "grade",
            "note" => %{"V" => "0"},
            "bareme" => %{"V" => "10"},
            "service" => %{"V" => %{"L" => "Maths #{id}"}},
            "date" => %{"V" => "17/09/2026"},
            "moyenne" => %{"V" => "7,5"},
            "noteMin" => %{"V" => "0"},
            "noteMax" => %{"V" => "10"}
          }
        ]
      },
      "listeServices" => %{
        "V" => [
          %{
            "N" => "maths",
            "L" => "Maths",
            "moyEleve" => %{"V" => "14,25"},
            "baremeMoyEleve" => %{"V" => "20"}
          }
        ]
      }
    }

    {data, state, nil, false}
  end

  defp data("ListeMessagerie", payload, state) do
    assert (state.options[:space] || 2) in [2, 3]

    expected =
      if state.options[:space] == 3,
        do: %{"onglet" => 131},
        else: %{"onglet" => 131, "membre" => %{"N" => "child-a", "G" => 4}}

    assert payload["Signature"] == expected

    {%{
       "listeEtiquettes" => %{"V" => []},
       "listeMessagerie" => %{
         "V" => [
           %{
             "N" => "discussion",
             "estUneDiscussion" => true,
             "profondeur" => 0,
             "objet" => "Réunion",
             "lu" => state.discussion_read,
             "nbNonLus" => if(state.discussion_read, do: 0, else: 2),
             "listePossessionsMessages" => %{"V" => [%{"N" => "possession"}]}
           }
         ]
       }
     }, state, nil, false}
  end

  defp data("ListeMessages", payload, state) do
    expected =
      if state.options[:space] == 3,
        do: %{"onglet" => 131},
        else: %{"onglet" => 131, "membre" => %{"N" => "child-a", "G" => 4}}

    assert payload["Signature"] == expected
    assert payload["data"]["listePossessionsMessages"] == [%{"N" => "possession"}]

    {%{
       "listeMessages" => %{
         "V" =>
           for n <- 1..2 do
             %{
               "N" => "message-#{n}",
               "public_gauche" => "Professeur",
               "lu" => state.discussion_read,
               "date" => %{"V" => "18/09/2026 10:00:00"},
               "estHTML" => true,
               "contenu" => %{"V" => "<p>Bonjour</p><script>secret</script>"}
             }
           end
       }
     }, state, nil, false}
  end

  defp data("SaisieMessage", payload, state) do
    expected =
      if state.options[:space] == 3,
        do: %{"onglet" => 131},
        else: %{"onglet" => 131, "membre" => %{"N" => "child-a", "G" => 4}}

    assert payload["Signature"] == expected
    assert (state.options[:space] || 2) in [2, 3]
    assert payload["data"]["commande"] == "pourLu"
    assert payload["data"]["listePossessionsMessages"] == [%{"N" => "possession"}]
    {%{}, %{state | discussion_read: payload["data"]["lu"]}, nil, false}
  end

  defp data("PageAgenda", payload, state) do
    id = if state.options[:space] == 3, do: "child-a", else: payload["Signature"]["membre"]["N"]

    expected =
      if state.options[:space] == 3,
        do: %{"onglet" => 9},
        else: %{"onglet" => 9, "membre" => %{"N" => id, "G" => 4}}

    assert payload["Signature"] == expected

    assert payload["data"] == %{
             "AvecListeClasses" => true,
             "avecEventsPasses" => false,
             "avecRdvPartages" => true,
             "listeFamillesFiltre" => nil,
             "uniquementMesEvenements" => false
           }

    events =
      for {name, recipients} <- [{"A", ["Enfant A"]}, {"B", ["Enfant B"]}, {"Commun", []}] do
        %{
          "N" => name,
          "L" => "Événement #{name}",
          "listeEleves" => recipients,
          "Commentaire" => "Salle 203",
          "DateDebut" => %{"V" => "18/09/2026 12:55:00"},
          "DateFin" => %{"V" => "18/09/2026 14:45:00"}
        }
      end

    {%{"ListeEvenements" => events}, state, nil, false}
  end

  defp decode(value, state) do
    bytes = if state.options[:encrypted], do: decrypt(value, state.key, state.iv), else: value

    bytes =
      if state.options[:compressed] do
        bytes = if state.options[:encrypted], do: bytes, else: Base.decode16!(bytes, case: :mixed)
        inflate(bytes) |> Base.decode16!(case: :mixed)
      else
        bytes
      end

    if is_binary(bytes), do: Jason.decode!(bytes), else: bytes
  end

  defp encode(value, state) do
    bytes = Jason.encode!(value)

    bytes =
      if state.options[:compressed] do
        wrapped = :zlib.compress(bytes)
        binary_part(wrapped, 2, byte_size(wrapped) - 6)
      else
        bytes
      end

    cond do
      state.options[:encrypted] -> encrypt(bytes, state.key, state.iv)
      state.options[:compressed] -> Base.encode16(bytes)
      true -> value
    end
  end

  defp encrypt(bytes, key, iv) do
    pad = 16 - rem(byte_size(bytes), 16)

    :crypto.crypto_one_time(:aes_128_cbc, key, iv, bytes <> :binary.copy(<<pad>>, pad), true)
    |> Base.encode16(case: :lower)
  end

  defp decrypt(hex, key, iv) do
    bytes =
      :crypto.crypto_one_time(:aes_128_cbc, key, iv, Base.decode16!(hex, case: :mixed), false)

    binary_part(bytes, 0, byte_size(bytes) - :binary.last(bytes))
  end

  defp inflate(bytes) do
    z = :zlib.open()

    try do
      :zlib.inflateInit(z, -15)
      :zlib.inflate(z, bytes) |> IO.iodata_to_binary()
    after
      :zlib.close(z)
    end
  end
end
