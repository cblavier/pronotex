defmodule Pronotex.Pronote.SessionTest do
  use ExUnit.Case, async: true
  alias Pronotex.Pronote
  alias Pronotex.Pronote.{Config, Error, Session}
  alias Pronotex.Test.PronoteServer

  defp session(options \\ []) do
    options = Keyword.merge([encrypted: true, compressed: true], options)
    agent = start_supervised!({Agent, fn -> PronoteServer.initial(options) end})
    Req.Test.stub(__MODULE__, &PronoteServer.handle(&1, agent))

    config = %Config{
      url: "https://school.test/pronote/parent.html",
      username: "Parent",
      password: "PaSsWord-TEST"
    }

    student_agent =
      start_supervised!({Agent, fn -> PronoteServer.initial(Keyword.put(options, :space, 3)) end},
        id: :student_agent
      )

    Req.Test.stub(__MODULE__.Student, &PronoteServer.handle(&1, student_agent))
    student_config = %{config | url: "https://school.test/pronote/eleve.html", space: 3}
    student_configs = if options[:student], do: %{"child-a" => student_config}, else: %{}

    server =
      start_supervised!(
        {Session,
         name: nil,
         config: config,
         req_options: [plug: {Req.Test, __MODULE__}],
         student_configs: student_configs,
         student_req_options: [plug: {Req.Test, __MODULE__.Student}]}
      )

    Req.Test.allow(__MODULE__, self(), server)
    Req.Test.allow(__MODULE__.Student, self(), server)
    {server, if(options[:student], do: student_agent, else: agent)}
  end

  for {encrypted, compressed} <- [{false, false}, {true, false}, {false, true}, {true, true}] do
    test "login and timetable with encryption=#{encrypted}, compression=#{compressed}" do
      {server, agent} = session(encrypted: unquote(encrypted), compressed: unquote(compressed))
      assert {:ok, [%{id: "child-a"}, %{id: "child-b"}]} = Pronote.login(server)
      assert {:ok, [lesson]} = Pronote.lessons("child-b", ~D[2026-09-14], ~D[2026-09-20], server)
      assert lesson.child_id == "child-b"
      assert lesson.subject == "Maths child-b"
      assert lesson.start == ~N[2026-09-14 08:00:00]
      assert lesson.end == ~N[2026-09-14 08:55:00]
      assert lesson.canceled
      assert lesson.teachers == ["Professeur"]
      assert lesson.classrooms == ["Salle 12"]
      assert Agent.get(agent, & &1.logins) == 1
    end
  end

  test "both children reuse one session, concurrent reads remain correctly associated" do
    {server, agent} = session()
    parent = self()

    for id <- ["child-a", "child-b"] do
      start_supervised!(
        {Task,
         fn -> send(parent, {id, Pronote.lessons(id, ~D[2026-09-14], ~D[2026-09-20], server)}) end},
        id: id
      )
    end

    assert_receive {"child-a", {:ok, [%{subject: "Maths child-a"}]}}, 2000
    assert_receive {"child-b", {:ok, [%{subject: "Maths child-b"}]}}, 2000
    assert Agent.get(agent, & &1.logins) == 1
  end

  test "reads all weeks and filters dates inclusively" do
    {server, _} = session()
    assert {:ok, lessons} = Pronote.lessons("child-a", ~D[2026-09-15], ~D[2026-09-28], server)
    assert Enum.map(lessons, & &1.start) == [~N[2026-09-21 08:00:00], ~N[2026-09-28 08:00:00]]
  end

  test "reconnects once after an expired session and keeps the requested child" do
    {server, agent} = session(expire: true)

    assert {:ok, [%{child_id: "child-b"}]} =
             Pronote.lessons("child-b", ~D[2026-09-14], ~D[2026-09-20], server)

    assert Agent.get(agent, & &1.logins) == 2
  end

  test "does not loop on repeated expiry" do
    {server, agent} = session(expire: :always)

    assert {:error, %Error{reason: :session_expired}} =
             Pronote.lessons("child-a", ~D[2026-09-14], ~D[2026-09-20], server)

    assert Agent.get(agent, & &1.logins) == 2
  end

  test "rejects invalid ranges before any network request" do
    {server, agent} = session()

    assert {:error, %Error{reason: :invalid_dates}} =
             Pronote.lessons("child-a", ~D[2026-09-20], ~D[2026-09-14], server)

    assert Agent.get(agent, & &1.logins) == 0
  end

  test "rejects an unknown child" do
    {server, agent} = session()

    assert {:error, %Error{reason: :child_not_found}} =
             Pronote.lessons("other", ~D[2026-09-14], ~D[2026-09-20], server)

    refute Enum.any?(Agent.get(agent, & &1.calls), &(elem(&1, 0) == "PageEmploiDuTemps"))
  end

  test "rejects dates outside the school's year" do
    {server, _} = session()

    assert {:error, %Error{reason: :outside_school_year}} =
             Pronote.lessons("child-a", ~D[2025-09-14], ~D[2025-09-20], server)
  end

  test "does not access unauthorized tabs" do
    {server, _} = session(forbidden: true)

    assert {:error, %Error{reason: :forbidden}} =
             Pronote.lessons("child-a", ~D[2026-09-14], ~D[2026-09-20], server)
  end

  test "reports failed login without returning private data" do
    {server, agent} = session(bad_credentials: true)
    assert {:error, %Error{reason: :authentication_failed} = error} = Pronote.login(server)
    refute inspect(error) =~ "PaSsWord-TEST"
    assert Agent.get(agent, & &1.logins) == 1
  end

  test "reports extra authentication without changing account settings" do
    {server, agent} = session(mfa: true)
    assert {:error, %Error{reason: :additional_authentication_required}} = Pronote.login(server)

    refute Enum.any?(
             Agent.get(agent, & &1.calls),
             &(elem(&1, 0) == "SecurisationCompteDoubleAuth")
           )
  end

  test "logout drops the session; inspection hides credentials and keys" do
    {server, agent} = session()
    assert {:ok, _} = Pronote.login(server)
    refute inspect(:sys.get_status(server)) =~ "PaSsWord-TEST"
    assert :ok = Pronote.logout(server)
    assert {:ok, _} = Pronote.children(server)
    assert Agent.get(agent, & &1.logins) == 2
  end

  test "does not retry a failed POST and can reconnect on the next explicit read" do
    {server, agent} = session()
    assert {:ok, _} = Pronote.login(server)

    Req.Test.stub(__MODULE__, fn conn ->
      Agent.update(agent, &Map.update(&1, :http_errors, 1, fn n -> n + 1 end))
      Plug.Conn.send_resp(conn, 503, "private response")
    end)

    assert {:error, %Error{reason: :http, code: 503} = error} =
             Pronote.lessons("child-a", ~D[2026-09-14], ~D[2026-09-20], server)

    refute inspect(error) =~ "private response"
    assert Agent.get(agent, & &1.http_errors) == 1
    Req.Test.stub(__MODULE__, &PronoteServer.handle(&1, agent))
    assert {:ok, _} = Pronote.children(server)
    assert Agent.get(agent, & &1.logins) == 2
  end

  test "returns a safe network error without retrying" do
    {server, agent} = session()

    Req.Test.stub(__MODULE__, fn conn ->
      Agent.update(agent, &Map.update(&1, :http_errors, 1, fn n -> n + 1 end))
      Req.Test.transport_error(conn, :timeout)
    end)

    assert {:error, %Error{reason: :network}} = Pronote.login(server)
    assert Agent.get(agent, & &1.http_errors) == 1
  end

  test "does not retry authentication when the server rate limits it" do
    {server, agent} = session()

    Req.Test.stub(__MODULE__, fn conn ->
      if conn.method == "POST" do
        Req.Test.json(conn, %{"Erreur" => %{"G" => 25, "Titre" => "private details"}})
      else
        PronoteServer.handle(conn, agent)
      end
    end)

    assert {:error, %Error{reason: :rate_limited, code: 25} = error} = Pronote.login(server)
    refute inspect(error) =~ "private details"
    assert Agent.get(agent, & &1.logins) == 1
  end

  test "rejects redirects and never sends credentials to another origin" do
    {server, agent} = session()

    Req.Test.stub(__MODULE__, fn conn ->
      Agent.update(agent, &Map.update(&1, :http_errors, 1, fn n -> n + 1 end))

      conn
      |> Plug.Conn.put_resp_header("location", "https://other.test/")
      |> Plug.Conn.send_resp(302, "")
    end)

    assert {:error, %Error{reason: :http, code: 302}} = Pronote.login(server)
    assert Agent.get(agent, & &1.http_errors) == 1
  end

  test "malformed payloads are sanitized, without crashing the session" do
    {server, _} = session()

    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(200, "private malformed body")
    end)

    assert {:error, %Error{reason: :protocol} = error} = Pronote.login(server)
    refute inspect(error) =~ "private malformed body"
    assert :ok = Pronote.logout(server)
  end

  test "reads homework with the parent signature and filters inclusive due dates" do
    {server, agent} = session()
    assert {:ok, [homework]} = Pronote.homework("child-b", ~D[2026-09-15], ~D[2026-09-24], server)
    assert homework.child_id == "child-b"
    assert homework.date == ~D[2026-09-17]
    assert homework.subject == "Français child-b"
    assert homework.done
    assert homework.description == "Lire le chapitre & réviser."
    assert homework.description =~ "& réviser."
    refute homework.description =~ "<"
    refute homework.description =~ "alert"
    calls = Agent.get(agent, & &1.calls)
    refute Enum.any?(calls, fn {name, _} -> name == "SaisieTAFFaitEleve" end)
  end

  test "homework rejects invalid dates without connecting" do
    {server, agent} = session()

    assert {:error, %Error{reason: :invalid_dates}} =
             Pronote.homework("child-a", ~D[2026-09-20], ~D[2026-09-14], server)

    assert Agent.get(agent, & &1.logins) == 0
  end

  test "homework cannot request a different parent's child" do
    {server, agent} = session()

    assert {:error, %Error{reason: :child_not_found}} =
             Pronote.homework("unknown", ~D[2026-09-15], ~D[2026-09-24], server)

    refute Enum.any?(Agent.get(agent, & &1.calls), &(elem(&1, 0) == "PageCahierDeTexte"))
  end

  test "menus share the encrypted session, span weeks and filter inclusive dates" do
    {server, agent} = session()
    assert {:ok, _} = Pronote.children(server)
    assert {:ok, [menu]} = Pronote.menus("child-b", ~D[2026-09-17], ~D[2026-09-23], server)
    assert menu.date == ~D[2026-09-21]
    assert menu.kind == "Déjeuner"

    assert menu.courses == [
             %{label: "Plats", foods: ["Gratin"]},
             %{label: "Desserts", foods: ["Pomme"]}
           ]

    assert Agent.get(agent, & &1.logins) == 1

    assert {:error, %Error{reason: :invalid_dates}} =
             Pronote.menus("child-b", ~D[2026-09-23], ~D[2026-09-17], server)
  end

  test "menus respect tab permissions" do
    {server, _} = session(forbidden: true)

    assert {:error, %Error{reason: :forbidden}} =
             Pronote.menus("child-a", ~D[2026-09-14], ~D[2026-09-20], server)
  end

  test "grades use the child signature and period in the existing encrypted session" do
    {server, agent} = session()
    assert {:ok, report} = Pronote.grades("child-b", nil, server)
    assert report.period == "Semestre 1"
    assert report.periods == ["Semestre 1", "Semestre 2"]
    assert report.overall == "14,25"

    assert [
             %{
               score: "0",
               out_of: "10",
               average: "7,5",
               min: "0",
               max: "10",
               subject: "Maths child-b"
             }
           ] = report.grades

    assert [%{score: "14,25", average: nil}] = report.averages
    assert {:ok, %{period: "Semestre 2"}} = Pronote.grades("child-a", "semester2", server)
    assert Agent.get(agent, & &1.logins) == 1
    assert {:ok, %{period: "Semestre 1"}} = Pronote.grades("child-a", "Unknown", server)
  end

  test "grades reject forbidden and unknown children" do
    {server, _} = session(forbidden: true)
    assert {:error, %Error{reason: :forbidden}} = Pronote.grades("child-a", nil, server)
    assert {:error, %Error{reason: :child_not_found}} = Pronote.grades("unknown", nil, server)
  end

  test "events use the encrypted parent session and filter child recipients" do
    {server, agent} = session()
    assert {:ok, a} = Pronote.events("child-a", server)
    assert Enum.map(a, & &1.title) == ["Événement A", "Événement Commun"]
    assert hd(a).start == ~N[2026-09-18 12:55:00]
    assert hd(a).end == ~N[2026-09-18 14:45:00]
    assert {:ok, b} = Pronote.events("child-b", server)
    assert Enum.map(b, & &1.title) == ["Événement B", "Événement Commun"]
    assert Agent.get(agent, & &1.logins) == 1
    assert {:error, %Error{reason: :child_not_found}} = Pronote.events("unknown", server)
  end

  test "events respect tab permissions" do
    {server, _} = session(forbidden: true)
    assert {:error, %Error{reason: :forbidden}} = Pronote.events("child-a", server)
  end

  test "student checks and unchecks through a separate session" do
    {server, agent} = session(student: true)
    assert {:ok, [_]} = Pronote.homework("child-a", ~D[2026-09-15], ~D[2026-09-24], server)
    assert {:ok, [%{done: false}]} = Pronote.set_homework_done("child-a", "hw-due", false, server)
    assert {:ok, [%{done: true}]} = Pronote.set_homework_done("child-a", "hw-due", true, server)
    assert Agent.get(agent, & &1.logins) == 1

    assert {:error, %Error{reason: :stale_homework}} =
             Pronote.set_homework_done("child-a", "unknown", false, server)

    assert Enum.count(Agent.get(agent, & &1.calls), &(elem(&1, 0) == "SaisieTAFFaitEleve")) == 2
  end

  test "unconfirmed writes are errors, not optimistic success" do
    {server, _} = session(ignore_write: true, student: true)
    Pronote.homework("child-a", ~D[2026-09-15], ~D[2026-09-24], server)

    assert {:error, %Error{reason: :homework_unconfirmed}} =
             Pronote.set_homework_done("child-a", "hw-due", false, server)
  end

  test "expired writes are never replayed and stale IDs require a fresh read" do
    {server, agent} = session(write_error: 10, student: true)
    Pronote.homework("child-a", ~D[2026-09-15], ~D[2026-09-24], server)

    assert {:error, %Error{reason: :session_expired}} =
             Pronote.set_homework_done("child-a", "hw-due", false, server)

    assert Agent.get(agent, & &1.logins) == 1

    assert {:error, %Error{reason: :stale_homework}} =
             Pronote.set_homework_done("child-a", "hw-due", false, server)

    assert Enum.count(Agent.get(agent, & &1.calls), &(elem(&1, 0) == "SaisieTAFFaitEleve")) == 1
  end

  test "writes reject malformed statuses before contacting Pronote" do
    {server, agent} = session()

    assert {:error, %Error{reason: :invalid_homework}} =
             Pronote.set_homework_done("child-a", "hw-due", "false", server)

    assert Agent.get(agent, & &1.logins) == 0
  end

  test "missing student credentials never send a parent write" do
    {server, agent} = session()
    Pronote.homework("child-a", ~D[2026-09-15], ~D[2026-09-24], server)

    assert {:error, %Error{reason: :student_credentials_required}} =
             Pronote.set_homework_done("child-a", "hw-due", false, server)

    refute Enum.any?(Agent.get(agent, & &1.calls), &(elem(&1, 0) == "SaisieTAFFaitEleve"))
  end

  test "wrong student identity prevents the write" do
    {server, agent} = session(student: true, wrong_student: true)
    Pronote.homework("child-a", ~D[2026-09-15], ~D[2026-09-24], server)

    assert {:error, %Error{reason: :student_mismatch}} =
             Pronote.set_homework_done("child-a", "hw-due", false, server)

    refute Enum.any?(Agent.get(agent, & &1.calls), &(elem(&1, 0) == "SaisieTAFFaitEleve"))
  end
end
