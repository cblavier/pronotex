defmodule PronotexWeb.DashboardLiveTest do
  use PronotexWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  test "dashboard redirects without a selected authenticated profile" do
    assert {:error, {:redirect, %{to: "/login"}}} = live(build_conn(), "/alice")
  end

  test "an open live page redirects when authentication expires", %{conn: conn} do
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    send(view.pid, :auth_expired)
    assert_redirect(view, "/login")
  end

  defmodule API do
    def children do
      notify(:children)

      case Application.get_env(:pronotex, :dashboard_test_mode) do
        :failure ->
          {:error, Pronotex.Pronote.Error.new(:network)}

        :no_children ->
          {:ok, []}

        :rotating_children ->
          generation = Process.get(:children_generation, 0) + 1
          Process.put(:children_generation, generation)
          {:ok, [%{id: "a-#{generation}", name: "Alice"}]}

        _ ->
          {:ok, [%{id: "a", name: "Alice"}, %{id: "b", name: "Basile"}]}
      end
    end

    def lessons(id, from, to) do
      notify({:lessons, id, from, to})

      from =
        if Application.get_env(:pronotex, :dashboard_test_mode) == :upcoming,
          do: Date.add(from, 3),
          else: from

      if Application.get_env(:pronotex, :dashboard_test_mode) == :pauses do
        {:ok,
         Enum.map([{~T[10:20:00], ~T[11:15:00]}, {~T[12:55:00], ~T[13:50:00]}], fn {start, ending} ->
           %Pronotex.Pronote.Lesson{
             id: Time.to_string(start),
             child_id: id,
             subject: "Maths #{id}",
             start: NaiveDateTime.new!(from, start),
             end: NaiveDateTime.new!(from, ending),
             lunch_window: %{
               start: NaiveDateTime.new!(from, ~T[12:10:00]),
               end: NaiveDateTime.new!(from, ~T[13:50:00])
             }
           }
         end)}
      else
        if Application.get_env(:pronotex, :dashboard_test_mode) == :empty do
          {:ok, []}
        else
          {:ok,
           [
             %Pronotex.Pronote.Lesson{
               id: "course",
               contents:
                 if(Application.get_env(:pronotex, :dashboard_test_mode) == :lesson_content,
                   do: [
                     %{
                       title: "Fractions",
                       description: "Comparer des fractions",
                       resources: [
                         %{name: "Exercice", type: :link, url: "https://example.org/exercice"}
                       ]
                     }
                   ],
                   else: []
                 ),
               child_id: id,
               subject: "Maths #{id}",
               canceled: Application.get_env(:pronotex, :dashboard_test_mode) == :canceled,
               start: NaiveDateTime.new!(from, ~T[08:00:00]),
               end: NaiveDateTime.new!(from, ~T[09:00:00])
             }
           ]}
        end
      end
    end

    def homework(id, from, to) do
      notify({:homework, id, from, to})

      if Application.get_env(:pronotex, :dashboard_test_mode) == :slow_homework do
        notify({:homework_pending, self()})

        receive do
          :finish_homework -> :ok
        end
      end

      case Application.get_env(:pronotex, :dashboard_test_mode) do
        :empty ->
          {:ok, []}

        :upcoming ->
          {:ok,
           Enum.map([1, 3], fn offset ->
             %Pronotex.Pronote.Homework{
               id: "task-#{offset}",
               child_id: id,
               subject: "Français",
               date: Date.add(from, offset),
               description: "Lire."
             }
           end)}

        :partial_failure ->
          {:error, Pronotex.Pronote.Error.new(:forbidden)}

        _ ->
          {:ok,
           [
             %Pronotex.Pronote.Homework{
               id: "task",
               child_id: id,
               subject: "Français #{id}",
               date: from,
               description: "Lire <script>danger</script> le chapitre."
             }
           ]}
      end
    end

    def discussions(id) do
      mode = Application.get_env(:pronotex, :dashboard_test_mode)

      if mode == :communications do
        {:ok,
         for kind <- [:discussion, :information, :survey] do
           %{
             id: "#{kind}-#{id}",
             kind: kind,
             acknowledgement_required: kind == :information,
             acknowledged: false,
             can_acknowledge: kind == :information,
             subject: "Sujet #{kind}",
             author: "Établissement",
             date: "09/09/2026 11:22:35",
             unread: 1,
             preview: "Contenu",
             messages: [
               %{
                 id: "entry",
                 author: "Établissement",
                 date: "09/09/2026 11:22:35",
                 content: "Contenu #{kind}",
                 resources: [%{name: "Fichier", url: "https://school.test/file.pdf"}],
                 choices: ["Oui", "Non"]
               }
             ]
           }
         end}
      else
        if mode == :messages do
          {:ok,
           [
             %{
               id: "thread-#{id}",
               subject: "Discussion #{id}",
               author: "Professeur",
               date: "18/09/2026",
               unread: 2,
               preview: "Bonjour",
               messages: [
                 %{
                   id: "m1",
                   author: "Professeur",
                   date: "18/09/2026",
                   content: "<script>privé</script>"
                 }
               ]
             },
             %{
               id: "other-#{id}",
               subject: "Autre discussion",
               author: "Autre professeur",
               date: "18/09/2026",
               unread: 0,
               preview: "Autre contenu",
               messages: [
                 %{
                   id: "m2",
                   author: "Autre professeur",
                   date: "18/09/2026",
                   content: "Autre contenu"
                 }
               ]
             }
           ]}
        else
          {:ok, []}
        end
      end
    end

    def parent_discussions do
      notify(:parent_discussions)
      discussions("parent")
    end

    def set_parent_discussion_read(thread, read) do
      notify({:mark_parent_discussion, thread, read})
      {:ok, rows} = discussions("parent")

      {:ok,
       Enum.map(rows, fn row ->
         cond do
           row.id != thread ->
             row

           Map.get(row, :kind) == :information ->
             %{row | acknowledged: true, can_acknowledge: false, unread: 0}

           true ->
             %{row | unread: if(read, do: 0, else: 2)}
         end
       end)}
    end

    def set_discussion_read(id, thread, read) do
      notify({:mark_discussion, id, thread, read})
      {:ok, rows} = discussions(id)

      {:ok,
       Enum.map(rows, fn row ->
         cond do
           row.id != thread ->
             row

           Map.get(row, :kind) == :information ->
             %{row | acknowledged: true, can_acknowledge: false, unread: 0}

           true ->
             %{row | unread: if(read, do: 0, else: 2)}
         end
       end)}
    end

    def homework_writable?(_child),
      do: Application.get_env(:pronotex, :dashboard_test_mode) != :no_student

    def set_homework_done(id, task, done) do
      notify({:write_homework, id, task, done})

      case Application.get_env(:pronotex, :dashboard_test_mode) do
        :write_failure ->
          {:error, Pronotex.Pronote.Error.new(:forbidden)}

        mode ->
          if mode == :slow_write do
            notify({:write_pending, self()})

            receive do
              :finish_write -> :ok
            end
          end

          {:ok, tasks} = homework(id, ~D[2026-09-18], ~D[2026-09-24])
          {:ok, Enum.map(tasks, &%{&1 | done: done})}
      end
    end

    def events(id) do
      notify({:events, id})

      case Application.get_env(:pronotex, :dashboard_test_mode) do
        :empty ->
          {:ok, []}

        :many_events ->
          {:ok,
           for n <- 1..12 do
             %Pronotex.Pronote.Event{
               id: "event-#{n}",
               title: "Évènement #{id} #{n}",
               description: "",
               start: ~N[2026-10-05 17:00:00],
               end: ~N[2026-10-05 18:00:00]
             }
           end}

        :rotating_children when id == "a-1" ->
          {:error, Pronotex.Pronote.Error.new(:child_not_found)}

        :inaccessible_child ->
          {:error, Pronotex.Pronote.Error.new(:child_not_found)}

        :events_failure ->
          {:error, Pronotex.Pronote.Error.new(:forbidden)}

        _ ->
          {:ok,
           [
             %Pronotex.Pronote.Event{
               id: "event",
               title: "Réunion #{id}",
               description: "Salle 203\n<script>test</script>",
               start: ~N[2026-10-05 17:00:00],
               end: ~N[2026-10-05 18:00:00]
             }
           ]}
      end
    end

    def menus(id, from, to) do
      notify({:menus, id, from, to})

      case Application.get_env(:pronotex, :dashboard_test_mode) do
        :empty ->
          {:ok, []}

        :failure ->
          {:error, Pronotex.Pronote.Error.new(:forbidden)}

        _ ->
          {:ok,
           [
             %Pronotex.Pronote.Menu{
               id: "meal",
               date: from,
               kind: "Déjeuner",
               courses: [%{label: "Plats", foods: ["Gratin"]}]
             }
           ]}
      end
    end

    def grades(id, period) do
      notify({:grades, id, period})
      mode = Application.get_env(:pronotex, :dashboard_test_mode)

      report =
        Pronotex.Pronote.Grades.parse(%{
          "moyGenerale" => %{"V" => "14,5"},
          "baremeMoyGenerale" => %{"V" => "20"},
          "listeDevoirs" => %{
            "V" => [
              %{
                "N" => "g",
                "note" => %{"V" => "12"},
                "bareme" => %{"V" => "20"},
                "date" => %{"V" => "17/09/2026"},
                "service" => %{"V" => %{"L" => "Maths #{id}"}},
                "moyenne" => %{"V" => "11"},
                "noteMin" => %{"V" => "3"},
                "noteMax" => %{"V" => "19"}
              }
            ]
          },
          "listeServices" => %{
            "V" => [
              %{
                "N" => "m",
                "L" => "Maths #{id}",
                "moyEleve" => %{"V" => "14,5"},
                "baremeMoyEleve" => %{"V" => "20"}
              }
            ]
          }
        })

      case mode do
        :grades_failure ->
          {:error, Pronotex.Pronote.Error.new(:forbidden)}

        _ ->
          report = if mode == :empty, do: Pronotex.Pronote.Grades.parse(%{}), else: report

          {:ok,
           Map.merge(report, %{
             period: if(period == "semester2", do: "Semestre 2", else: "Semestre 1"),
             periods: ["Semestre 1", "Semestre 2"]
           })}
      end
    end

    defp notify(message),
      do: send(Application.fetch_env!(:pronotex, :dashboard_test_pid), message)
  end

  defmodule ChildAPI do
    alias PronotexWeb.DashboardLiveTest.API
    def children, do: {:ok, [%{id: "a", name: "Alice"}]}
    defdelegate lessons(id, from, to), to: API
    defdelegate homework(id, from, to), to: API
    defdelegate events(id), to: API
    defdelegate discussions(id), to: API
    defdelegate homework_writable?(child), to: API
  end

  setup do
    keys = [:pronote_client, :dashboard_test_pid, :dashboard_test_mode, :today, :now]
    previous = Map.new(keys, &{&1, Application.fetch_env(:pronotex, &1)})
    Application.put_env(:pronotex, :today, fn -> ~D[2026-09-18] end)
    Application.put_env(:pronotex, :now, fn -> ~N[2026-09-18 12:00:00] end)
    Application.put_env(:pronotex, :pronote_client, API)
    Application.put_env(:pronotex, :dashboard_test_pid, self())
    Application.delete_env(:pronotex, :dashboard_test_mode)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:pronotex, key, value)
        {key, :error} -> Application.delete_env(:pronotex, key)
      end)
    end)

    :ok
  end

  test "agenda fetches lessons and urgent homework on connected mount", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    render_async(view)
    assert has_element?(view, "#child-name", "Alice")
    assert has_element?(view, "#timetable #lesson-days", "Maths a")
    assert has_element?(view, "#homework-content[hidden]")
    refute has_element?(view, "#homework script")
    assert_receive :children
    assert_receive {:lessons, "a", from, to}
    assert from == ~D[2026-09-18]
    assert_patch(view, "/alice")
    assert has_element?(view, "#today-view[aria-pressed=true]")
    assert has_element?(view, "#next-week")
    assert has_element?(view, "#previous-week")
    refute has_element?(view, "#week-view")
    assert to == ~D[2026-09-18]
    refute_received {:lessons, _, _, _}
    assert_receive {:homework, "a", ~D[2026-09-18], ~D[2026-09-19]}
  end

  test "switching child replaces timetable and reloads on return", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    render_async(view)
    view |> element(".child-picker-option[data-child-id]:not([aria-current])") |> render_click()
    render_async(view)
    assert has_element?(view, "#child-name", "Basile")
    assert has_element?(view, "#lesson-days", "Maths b")

    refute has_element?(view, "#lesson-days", "Maths a")
    refute has_element?(view, "#homework-days", "Français a")
    assert_receive {:lessons, "b", _, _}
    view |> element(".child-picker-option[data-child-id]:not([aria-current])") |> render_click()
    render_async(view)
    assert has_element?(view, "#child-name", "Alice")
    assert_receive {:lessons, "a", _, _}
    assert_receive {:lessons, "a", _, _}
  end

  test "week navigation and refresh fetch data again", %{conn: conn} do
    {:ok, view, _} = live(conn, "/alice?week=2026-09-14")
    render_async(view)
    assert_receive {:lessons, "a", from, _}
    view |> element("#next-week") |> render_click()
    render_async(view)
    assert_receive {:lessons, "a", next, _}
    assert next == Date.add(from, 7)
    render_click(view, "refresh", %{})
    render_async(view)
    assert_receive {:lessons, "a", ^next, _}
  end

  test "reopening the page does not reuse cached data", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    render_async(view)
    {:ok, another, _} = live(conn, ~p"/")
    render_async(another)
    assert_receive {:lessons, "a", _, _}
    assert_receive {:lessons, "a", _, _}
  end

  test "shows empty states", %{conn: conn} do
    Application.put_env(:pronotex, :dashboard_test_mode, :empty)
    {:ok, view, _} = live(conn, ~p"/")
    render_async(view)
    assert has_element?(view, "#no-lessons-today")
    view |> element("#nav-devoirs") |> render_click()
    render_async(view)
    assert has_element?(view, "#no-homework")
  end

  test "homework errors do not prevent opening the agenda", %{conn: conn} do
    Application.put_env(:pronotex, :dashboard_test_mode, :partial_failure)
    {:ok, view, _} = live(conn, ~p"/")
    render_async(view)
    assert has_element?(view, "#lesson-days", "Maths a")
    view |> element("#nav-devoirs") |> render_click()
    render_async(view)
    assert has_element?(view, "#flash-error")
    refute has_element?(view, "#no-homework")
    view |> element("#nav-agenda") |> render_click()
    render_async(view)
    assert has_element?(view, "#lesson-days", "Maths a")
  end

  test "failed initialization can be retried", %{conn: conn} do
    Application.put_env(:pronotex, :dashboard_test_mode, :failure)
    {:ok, view, _} = live(conn, ~p"/")
    render_async(view)
    assert has_element?(view, "#flash-error")
    refute has_element?(view, "#no-lessons")
    Application.delete_env(:pronotex, :dashboard_test_mode)
    view |> element("#retry-error") |> render_click()
    render_async(view)
    refute has_element?(view, "#flash-error")
    assert has_element?(view, "#child-name", "Alice")
  end

  test "a direct URL restores the selected child and week", %{conn: conn} do
    {:ok, view, _} = live(conn, "/basile?week=2026-09-21")
    render_async(view)
    assert has_element?(view, "#child-name", "Basile")
    assert has_element?(view, "#week-label", "du 21/09 au 27/09/2026")
    assert_receive {:lessons, "b", ~D[2026-09-21], ~D[2026-09-27]}
    refute_received {:lessons, "a", _, _}
  end

  test "child and week controls update the URL while retaining the other selection", %{conn: conn} do
    {:ok, view, _} = live(conn, "/alice?week=2026-09-14")
    render_async(view)
    view |> element(".child-picker-option[data-child-id]:not([aria-current])") |> render_click()
    assert_patch(view, "/basile?week=2026-09-14")
    render_async(view)
    view |> element("#next-week") |> render_click()
    assert_patch(view, "/basile?week=2026-09-21")
    render_async(view)
    render_patch(view, "/alice?week=2026-09-14")
    render_async(view)
    assert has_element?(view, "#child-name", "Alice")
    assert has_element?(view, "#week-label", "14/09")
    assert has_element?(view, "#lesson-days", "Maths a")
  end

  test "midweek URLs normalize to Monday without duplicate API reads", %{conn: conn} do
    {:ok, view, _} = live(conn, "/basile?week=2026-09-17")
    render_async(view)
    assert_patch(view, "/basile?week=2026-09-14")
    render_async(view)
    assert_receive {:lessons, "b", ~D[2026-09-14], _}
    refute_received {:lessons, _, _, _}
  end

  test "unknown children and invalid dates fall back to a canonical URL", %{conn: conn} do
    {:ok, view, _} = live(conn, "/unknown?week=invalid")
    render_async(view)
    assert_patch(view, "/alice")
    render_async(view)
    assert has_element?(view, "#child-name", "Alice")
    assert_receive {:lessons, "a", ~D[2026-09-18], ~D[2026-09-18]}
    refute_received {:lessons, _, _, _}
  end

  test "today timetable shows weekdays through Friday and advances on weekends", %{conn: conn} do
    for {date, first, last} <- [
          {~D[2026-09-14], ~D[2026-09-14], ~D[2026-09-18]},
          {~D[2026-09-16], ~D[2026-09-16], ~D[2026-09-18]},
          {~D[2026-09-18], ~D[2026-09-18], ~D[2026-09-18]},
          {~D[2026-09-19], ~D[2026-09-21], ~D[2026-09-25]},
          {~D[2026-09-20], ~D[2026-09-21], ~D[2026-09-25]}
        ] do
      Application.put_env(:pronotex, :today, fn -> date end)
      {:ok, view, _} = live(conn, "/alice")
      render_async(view)
      assert_receive {:lessons, "a", ^first, ^last}

      if Date.day_of_week(date) > 5 do
        refute has_element?(view, "#no-lessons-today")
        refute has_element?(view, "#lesson-days h3", "Aujourd’hui")
        assert has_element?(view, "#lesson-days", "Maths a")
      end
    end
  end

  test "today agenda advances at 18h and skips the weekend", %{conn: conn} do
    for {date, first, last} <- [
          {~D[2026-09-16], ~D[2026-09-17], ~D[2026-09-18]},
          {~D[2026-09-18], ~D[2026-09-21], ~D[2026-09-25]},
          {~D[2026-09-20], ~D[2026-09-21], ~D[2026-09-25]}
        ] do
      Application.put_env(:pronotex, :today, fn -> date end)
      Application.put_env(:pronotex, :now, fn -> NaiveDateTime.new!(date, ~T[18:00:00]) end)
      {:ok, view, _} = live(conn, "/alice")
      render_async(view)
      assert_receive {:lessons, "a", ^first, ^last}
      refute has_element?(view, "#no-lessons-today")
    end
  end

  test "an open agenda advances when the clock reaches 18h", %{conn: conn} do
    Application.put_env(:pronotex, :now, fn -> ~N[2026-09-18 17:59:59] end)
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    assert_receive {:lessons, "a", ~D[2026-09-18], ~D[2026-09-18]}
    Application.put_env(:pronotex, :now, fn -> ~N[2026-09-18 18:00:00] end)
    send(view.pid, :update_lesson_clock)
    render(view)
    render_async(view)
    assert_receive {:lessons, "a", ~D[2026-09-21], ~D[2026-09-25]}
  end

  test "today and week modes retain the child and support browser navigation", %{conn: conn} do
    {:ok, view, _} = live(conn, "/basile?week=2026-09-07")
    render_async(view)
    view |> element("#today-view") |> render_click()
    assert_patch(view, "/basile")
    render_async(view)
    assert_receive {:lessons, "b", ~D[2026-09-18], ~D[2026-09-18]}
    assert has_element?(view, "#lesson-days h3", "Aujourd’hui")

    view |> element("#previous-week") |> render_click()
    assert_patch(view, "/basile?week=2026-09-14")
    render_async(view)
    assert_receive {:lessons, "b", ~D[2026-09-14], ~D[2026-09-20]}
    render_patch(view, "/basile")
    render_async(view)
    assert has_element?(view, "#today-view[aria-pressed=true]")
    view |> element(".child-picker-option[data-child-id]:not([aria-current])") |> render_click()
    assert_patch(view, "/alice")
    render_async(view)
    assert_receive {:lessons, "a", ~D[2026-09-18], ~D[2026-09-18]}
  end

  test "refresh rolls the today range forward after midnight", %{conn: conn} do
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    Application.put_env(:pronotex, :today, fn -> ~D[2026-09-19] end)
    render_click(view, "refresh", %{})
    render_async(view)
    assert_receive {:lessons, "a", ~D[2026-09-21], ~D[2026-09-25]}
    assert has_element?(view, "#week-label", "à partir d’aujourd’hui")
    refute has_element?(view, "#week-label", "19/09")
  end

  test "today remains visible without lessons and homework uses relative due dates", %{conn: conn} do
    Application.put_env(:pronotex, :dashboard_test_mode, :upcoming)
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    assert has_element?(view, "#lesson-days > section:first-child h3", "Aujourd’hui")
    assert has_element?(view, "#no-lessons-today")
    assert has_element?(view, "#lesson-days > section:last-child h3", "Lundi 21/09")
    view |> element("#nav-devoirs") |> render_click()
    render_async(view)
    assert has_element?(view, "#homework-days > section:first-child h3", "Pour demain")
    assert has_element?(view, "#homework-days > section:last-child h3", "Pour lundi 21/09")
  end

  test "arrows from Thursday open the current Monday or the following Monday", %{conn: conn} do
    Application.put_env(:pronotex, :today, fn -> ~D[2026-09-17] end)
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    view |> element("#previous-week") |> render_click()
    assert_patch(view, "/alice?week=2026-09-14")
    render_async(view)
    assert_receive {:lessons, "a", ~D[2026-09-14], ~D[2026-09-20]}
    view |> element("#previous-week") |> render_click()
    assert_patch(view, "/alice?week=2026-09-07")
    render_async(view)
    view |> element("#today-view") |> render_click()
    assert_patch(view, "/alice")
    render_async(view)
    assert_receive {:lessons, "a", ~D[2026-09-17], ~D[2026-09-18]}
    view |> element("#next-week") |> render_click()
    assert_patch(view, "/alice?week=2026-09-21")
    render_async(view)
    assert_receive {:lessons, "a", ~D[2026-09-21], ~D[2026-09-27]}
  end

  test "header groups dates and provides section navigation without a refresh button", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    refute has_element?(view, "#refresh")
    assert has_element?(view, "#date-navigation #previous-week")
    assert has_element?(view, "#date-navigation #next-week")
    assert has_element?(view, "#date-navigation #today-view")
    view |> element("#nav-notes") |> render_click()
    render_async(view)
    assert has_element?(view, "#grades-content:not([hidden])")
    assert has_element?(view, "#agenda-content[hidden]")
    refute has_element?(view, "#date-navigation")
    view |> element("#nav-cantine") |> render_click()
    render_async(view)
    assert has_element?(view, "#menu-days", "Gratin")
    assert_receive {:menus, "a", ~D[2026-09-18], ~D[2026-09-24]}
    view |> element("#nav-agenda") |> render_click()
    render_async(view)
    refute has_element?(view, "#agenda-content[hidden]")
    assert has_element?(view, "#lesson-days", "Maths a")
    assert has_element?(view, "#date-navigation")
  end

  test "canteen reloads the selected dates and child and handles empty menus", %{conn: conn} do
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    view |> element("#nav-cantine") |> render_click()
    render_async(view)
    view |> element("#next-week") |> render_click()
    render_async(view)
    assert_receive {:menus, "a", ~D[2026-09-21], ~D[2026-09-27]}
    Application.put_env(:pronotex, :dashboard_test_mode, :empty)
    view |> element(".child-picker-option[data-child-id]:not([aria-current])") |> render_click()
    render_async(view)
    assert_receive {:menus, "b", ~D[2026-09-21], ~D[2026-09-27]}
    assert has_element?(view, "#no-menus")
    Application.put_env(:pronotex, :dashboard_test_mode, :failure)
    render_click(view, "refresh", %{})
    render_async(view)
    assert has_element?(view, "#flash-error")
    Application.delete_env(:pronotex, :dashboard_test_mode)
    view |> element("#retry-error") |> render_click()
    render_async(view)
    assert has_element?(view, "#menu-days", "Gratin")
  end

  test "notes display official averages and reload on period and child changes", %{conn: conn} do
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    refute_received {:grades, _, _}
    view |> element("#nav-notes") |> render_click()
    render_async(view)
    assert_receive {:grades, "a", nil}
    assert has_element?(view, "#overall-average", "14,5 / 20")
    assert has_element?(view, "#subject-averages", "Maths a")
    assert has_element?(view, "#grade-list", "Moy. classe : 11")
    assert has_element?(view, "#grade-list", "Min. : 3")
    assert has_element?(view, "#grade-list", "Max. : 19")
    assert has_element?(view, "#grades-content[data-panel=latest]")
    view |> element("#grades-panel-averages") |> render_click()
    assert has_element?(view, "#grades-content[data-panel=averages]")
    assert has_element?(view, "#grades-panel-averages[aria-pressed=true]")
    assert has_element?(view, "#subject-averages", "Maths a")
    view |> element("#grades-panel-latest") |> render_click()
    assert has_element?(view, "#grades-content[data-panel=latest]")
    assert has_element?(view, "#grade-list", "Maths a")
    refute_received {:grades, _, _}
    view |> form("#grade-period-form", %{"period" => "semester2"}) |> render_change()
    render_async(view)
    assert_receive {:grades, "a", "semester2"}
    view |> element(".child-picker-option[data-child-id]:not([aria-current])") |> render_click()
    render_async(view)
    assert_receive {:grades, "b", "semester2"}
    assert has_element?(view, "#grade-list", "Maths b")
    refute has_element?(view, "#grade-list", "Maths a")
  end

  test "notes show empty and failed states and can retry", %{conn: conn} do
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    Application.put_env(:pronotex, :dashboard_test_mode, :empty)
    view |> element("#nav-notes") |> render_click()
    render_async(view)
    assert has_element?(view, "#no-grades")
    assert has_element?(view, "#no-averages")
    assert has_element?(view, "#overall-average", "Non disponible")
    Application.put_env(:pronotex, :dashboard_test_mode, :grades_failure)
    view |> form("#grade-period-form", %{"period" => "semester2"}) |> render_change()
    render_async(view)
    assert has_element?(view, "#flash-error")
    refute has_element?(view, "#no-grades")
    Application.delete_env(:pronotex, :dashboard_test_mode)
    view |> element("#retry-error") |> render_click()
    render_async(view)
    assert has_element?(view, "#grade-list", "Maths a")
  end

  test "direct notes URL restores page, week and period without duplicate reads", %{conn: conn} do
    url = "/alice/notes?week=2026-09-21&period=semester2"
    {:ok, view, _} = live(conn, url)
    render_async(view)
    assert has_element?(view, "#nav-notes[aria-current=page]")

    assert has_element?(
             view,
             "#dashboard-navigation #grade-period-picker input[value=semester2][checked]"
           )

    assert_receive {:grades, "a", "semester2"}
    refute_received {:grades, _, _}
    view |> element("#nav-cantine") |> render_click()
    assert_patch(view, "/alice/menu?week=2026-09-21&period=semester2")
    render_async(view)
    assert_receive {:menus, "a", ~D[2026-09-21], ~D[2026-09-27]}
    view |> element("#next-week") |> render_click()
    assert_patch(view, "/alice/menu?week=2026-09-28&period=semester2")
    render_async(view)
    view |> element("#nav-agenda") |> render_click()
    assert_patch(view, "/alice?week=2026-09-28&period=semester2")
    render_async(view)
    view |> element("#nav-notes") |> render_click()
    assert_patch(view, "/alice/notes?week=2026-09-28&period=semester2")
    render_async(view)
    render_patch(view, url)
    render_async(view)
    assert has_element?(view, "#nav-notes[aria-current=page]")
    view |> element("#nav-agenda") |> render_click()
    render_async(view)
    assert has_element?(view, "#week-label", "21/09")
    view |> element("#today-view") |> render_click()
    assert_patch(view, "/alice?period=semester2")
    render_async(view)
    {:ok, reopened, _} = live(conn, url)
    render_async(reopened)
    assert has_element?(reopened, "#grade-period-picker input[value=semester2][checked]")
  end

  test "notes canonicalize default and invalid periods once", %{conn: conn} do
    {:ok, view, _} = live(conn, "/alice/notes?period=unknown")
    render_async(view)
    assert_patch(view, "/alice/notes?period=semester1")
    render_async(view)
    assert_receive {:grades, "a", "unknown"}
    refute_received {:grades, _, _}
    view |> form("#grade-period-form", %{"period" => "semester2"}) |> render_change()
    assert_patch(view, "/alice/notes?period=semester2")
    render_async(view)
    view |> element(".child-picker-option[data-child-id]:not([aria-current])") |> render_click()
    assert_patch(view, "/basile/notes?period=semester2")
    render_async(view)
    assert_receive {:grades, "b", "semester2"}
  end

  test "homework is a separate page preserving dates and period across sections and children", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/alice/devoirs?week=2026-09-21&period=semester2")
    render_async(view)
    assert has_element?(view, "#nav-devoirs[aria-current=page]")
    assert has_element?(view, "#homework-content:not([hidden])")
    assert has_element?(view, "#agenda-content[hidden]")
    assert has_element?(view, "#homework-days", "Français a")
    refute has_element?(view, "#homework script")
    assert_receive {:homework, "a", ~D[2026-09-21], ~D[2026-09-27]}
    refute_received {:lessons, _, _, _}
    assert_receive {:homework, "a", ~D[2026-09-18], ~D[2026-09-19]}
    view |> element("#next-week") |> render_click()
    assert_patch(view, "/alice/devoirs?week=2026-09-28&period=semester2")
    render_async(view)
    assert_receive {:homework, "a", ~D[2026-09-28], ~D[2026-10-04]}
    view |> element(".child-picker-option[data-child-id]:not([aria-current])") |> render_click()
    assert_patch(view, "/basile/devoirs?week=2026-09-28&period=semester2")
    render_async(view)
    assert has_element?(view, "#homework-days", "Français b")
    view |> element("#nav-agenda") |> render_click()
    assert_patch(view, "/basile?week=2026-09-28&period=semester2")
    render_async(view)
    assert has_element?(view, "#homework-content[hidden]")
    assert has_element?(view, "#agenda-content:not([hidden])")
    render_patch(view, "/basile/devoirs?week=2026-09-28&period=semester2")
    render_async(view)
    view |> element("#today-view") |> render_click()
    assert_patch(view, "/basile/devoirs?period=semester2")
    render_async(view)
    assert_receive {:homework, "b", ~D[2026-09-18], ~D[2026-09-24]}
    assert has_element?(view, "#homework-days h3", "Pour aujourd’hui")
  end

  test "browser title follows the child and current page", %{conn: conn} do
    {:ok, view, _} = live(conn, "/alice/devoirs")
    render_async(view)
    assert page_title(view) == "Alice - Devoirs"
    view |> element("#nav-notes") |> render_click()
    render_async(view)
    assert page_title(view) == "Alice - Notes"
    view |> element(".child-picker-option[data-child-id]:not([aria-current])") |> render_click()
    render_async(view)
    assert page_title(view) == "Basile - Notes"
    view |> element("#nav-cantine") |> render_click()
    render_async(view)
    assert page_title(view) == "Basile - Menu"
    view |> element("#nav-agenda") |> render_click()
    render_async(view)
    assert page_title(view) == "Basile - Agenda"
  end

  test "child profile cannot navigate to another child or the parent mailbox" do
    Application.put_env(:pronotex, :pronote_client, ChildAPI)
    Application.put_env(:pronotex, :dashboard_test_mode, :messages)
    conn = build_conn() |> Plug.Test.init_test_session(Pronotex.Auth.session("child-1"))
    {:ok, view, _} = live(conn, "/basile")
    render_async(view)
    assert_patch(view, "/alice")
    assert has_element?(view, "#child-name", "Alice")
    refute has_element?(view, "#child-picker", "Basile")
    refute has_element?(view, "#open-parent-messages")
    render_click(view, "select-child", %{"id" => "b"})
    assert has_element?(view, "#child-name", "Alice")
    render_patch(view, "/basile/parent-messages/thread-parent")
    render_async(view)
    assert_patch(view, "/alice")
    refute has_element?(view, "#messages-content")
    refute_received :parent_discussions
  end

  test "parents have a separate inbox with its own breadcrumb and unread status" do
    Application.put_env(:pronotex, :dashboard_test_mode, :messages)
    conn = build_conn() |> Plug.Test.init_test_session(Pronotex.Auth.session("parent-1"))
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    assert has_element?(view, "#open-parent-messages", "Messages Camille")
    assert has_element?(view, "#open-messages", "Messages Alice")
    assert has_element?(view, "#parent-messages-unread-count", "2")
    view |> element("#open-parent-messages") |> render_click()
    assert_patch(view, "/alice/parent-messages")
    render_async(view)
    assert has_element?(view, "#discussion-thread-parent")
    assert has_element?(view, "#messages-title", "Messages Camille")
    refute has_element?(view, "#discussion-thread-a")
    view |> element("#discussion-thread-parent a") |> render_click()
    assert_patch(view, "/alice/parent-messages/thread-parent")
    assert has_element?(view, "#messages-breadcrumb a", "Retour aux messages")
    view |> element(".communication-detail-header .discussion-status") |> render_click()
    render_async(view)
    assert_receive {:mark_parent_discussion, "thread-parent", true}
    refute_received {:mark_discussion, _, _, _}
    refute has_element?(view, "#parent-messages-unread-count")
    assert has_element?(view, "#messages-unread-count", "2")
    view |> element("#messages-breadcrumb a") |> render_click()
    assert_patch(view, "/alice/parent-messages")
    view |> element("#nav-agenda") |> render_click()
    assert_patch(view, "/alice")
    render_async(view)
    view |> element("#open-messages") |> render_click()
    render_async(view)
    assert has_element?(view, "#messages-title", "Messages Alice")
    view |> element("#discussion-thread-a a") |> render_click()
    assert has_element?(view, "#messages-breadcrumb a", "Retour aux messages")
  end

  test "family cannot open a parent's inbox even with a forged URL", %{conn: conn} do
    {:ok, view, _} = live(conn, "/alice/parent-messages/thread-parent")
    render_async(view)
    assert_patch(view, "/alice")
    refute has_element?(view, "#open-parent-messages")
    refute has_element?(view, "#messages-content")
    refute_received :parent_discussions
  end

  test "information button acknowledges explicitly and cannot undo confirmation", %{conn: conn} do
    Application.put_env(:pronotex, :dashboard_test_mode, :communications)
    {:ok, view, _} = live(conn, "/alice/messages/information-a")
    render_async(view)
    render_async(view)
    refute_received {:mark_discussion, _, _, _}
    assert has_element?(view, ".discussion-status[aria-pressed=false]", "Non lu")
    view |> element(".communication-detail-header .discussion-status") |> render_click()
    render_async(view)
    assert_receive {:mark_discussion, "a", "information-a", true}

    assert has_element?(
             view,
             ".discussion-status[disabled][aria-pressed=true]",
             "Lu"
           )

    render_click(view, "mark-discussion", %{"id" => "information-a"})
    refute_received {:mark_discussion, _, _, _}
  end

  test "all communication categories share the inbox and open separately", %{conn: conn} do
    Application.put_env(:pronotex, :dashboard_test_mode, :communications)
    {:ok, view, _} = live(conn, "/alice/messages")
    render_async(view)
    render_async(view)

    assert has_element?(
             view,
             ".communication-heading .communication-badge[data-kind=discussion][aria-label=Discussion] svg"
           )

    assert has_element?(
             view,
             ".communication-heading .communication-badge[data-kind=information][aria-label=Informations] svg"
           )

    assert has_element?(
             view,
             ".communication-heading .communication-badge[data-kind=survey][aria-label=Sondage] svg"
           )

    assert has_element?(view, "#messages-unread-count", "3")

    for kind <- [:discussion, :information, :survey] do
      assert has_element?(
               view,
               "#discussion-#{kind}-a .discussion-meta",
               "mercredi 09/09 à 11h22"
             )
    end

    view |> element("#discussion-survey-a .discussion-summary") |> render_click()
    assert has_element?(view, ".communication-detail-header", "Sujet survey")
    assert has_element?(view, "#discussion-body-survey-a", "Contenu survey")

    assert has_element?(
             view,
             "#discussion-body-survey-a .discussion-meta",
             "mercredi 09/09 à 11h22"
           )

    assert has_element?(
             view,
             ".lesson-resource-link[href='https://school.test/file.pdf']",
             "Fichier"
           )

    refute has_element?(view, "#discussion-information-a")
    refute has_element?(view, ".discussion-summary")
    assert has_element?(view, ".communication-detail-header .discussion-status", "Non lu")
  end

  test "messages are reached from dropdown with explicit read actions and badge updates", %{
    conn: conn
  } do
    Application.put_env(:pronotex, :dashboard_test_mode, :messages)
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    render_async(view)
    assert has_element?(view, "#messages-avatar-dot")
    assert has_element?(view, "#messages-unread-count", "2")
    refute has_element?(view, "#section-navigation #open-messages")
    view |> element("#open-messages") |> render_click()
    assert_patch(view, "/alice/messages")
    render_async(view)
    render_async(view)
    refute has_element?(view, "#date-navigation")
    view |> element("#discussion-thread-a .discussion-summary") |> render_click()
    assert_patch(view, "/alice/messages/thread-a")
    assert has_element?(view, ".communication-detail-header", "Discussion a")
    refute has_element?(view, ".discussion-summary")
    assert has_element?(view, ".discussion-status", "Non lu")
    refute_received {:mark_discussion, _, _, _}
    refute has_element?(view, "#messages-content script")
    assert has_element?(view, "#discussion-body-thread-a:not([hidden])")
    refute has_element?(view, "#discussion-other-a")
    refute has_element?(view, "#messages-content", "Autre contenu")
    view |> element(".communication-detail-header .discussion-status") |> render_click()
    render_async(view)
    assert_receive {:mark_discussion, "a", "thread-a", true}
    refute has_element?(view, "#messages-avatar-dot")
    assert has_element?(view, ".discussion-status[aria-pressed=true]", "Lu")
    refute has_element?(view, "#messages-unread-count")
    view |> element(".communication-detail-header .discussion-status") |> render_click()
    render_async(view)
    assert_receive {:mark_discussion, "a", "thread-a", false}
    assert has_element?(view, "#messages-unread-count", "2")
    view |> element("#messages-breadcrumb a", "Retour aux messages") |> render_click()
    assert_patch(view, "/alice/messages")
    assert has_element?(view, ".discussion-summary")
    refute has_element?(view, "#discussion-body-thread-a")
    view |> element("#discussion-other-a .discussion-summary") |> render_click()
    assert_patch(view, "/alice/messages/other-a")
    assert has_element?(view, "#discussion-body-other-a", "Autre contenu")
    refute has_element?(view, "#discussion-thread-a")
    view |> element(".child-picker-option[data-child-id]") |> render_click()
    render_async(view)
    render_async(view)
    assert has_element?(view, "#discussion-thread-b")
    refute has_element?(view, "#discussion-thread-a")
    view |> element("#nav-agenda") |> render_click()
    render_async(view)
    refute has_element?(view, "#messages-content")
  end

  test "a discussion can be opened directly and missing discussions have a way back", %{
    conn: conn
  } do
    Application.put_env(:pronotex, :dashboard_test_mode, :messages)
    {:ok, view, _} = live(conn, "/alice/messages/thread-a")
    render_async(view)
    render_async(view)
    assert has_element?(view, "#discussion-body-thread-a")
    assert has_element?(view, ".communication-detail-header", "Discussion a")
    refute has_element?(view, ".discussion-summary")
    render_patch(view, "/alice/messages/missing")
    assert has_element?(view, "#messages-content", "Cette discussion n’est plus disponible.")
    view |> element("#messages-breadcrumb a") |> render_click()
    assert_patch(view, "/alice/messages")
    assert has_element?(view, "#discussion-thread-a .discussion-summary")
  end

  test "messages explain missing student credentials", %{conn: conn} do
    Application.put_env(:pronotex, :dashboard_test_mode, :no_student)
    {:ok, view, _} = live(conn, "/alice/messages")
    render_async(view)
    assert has_element?(view, "#messages-content", "identifiants du compte élève")
    refute has_element?(view, "#messages-avatar-dot")
  end

  test "mobile agenda panel selection keeps loaded content", %{conn: conn} do
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    assert has_element?(view, "#agenda-content[data-panel=timetable]")
    view |> element("#agenda-panel-events") |> render_click()
    assert has_element?(view, "#agenda-panel-events[aria-pressed=true]")
    assert has_element?(view, "#agenda-content[data-panel=events]")
    assert has_element?(view, "#upcoming-events", "Réunion a")
    view |> element("#agenda-panel-timetable") |> render_click()
    assert has_element?(view, "#agenda-content[data-panel=timetable]")
    assert has_element?(view, "#lesson-days", "Maths a")
  end

  test "events show eight initially and reveal the rest on demand", %{conn: conn} do
    Application.put_env(:pronotex, :dashboard_test_mode, :many_events)
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    assert has_element?(view, "#upcoming-title", "Évènements")
    assert has_element?(view, "#upcoming-events article:nth-child(8)")
    refute has_element?(view, "#upcoming-events article:nth-child(9)")
    view |> element("#show-more-events") |> render_click()
    assert has_element?(view, "#upcoming-events article:nth-child(12)")
    refute has_element?(view, "#show-more-events")
    view |> element(".child-picker-option[data-child-id]") |> render_click()
    render_async(view)
    refute has_element?(view, "#upcoming-events article:nth-child(9)")
    assert has_element?(view, "#show-more-events")
  end

  test "reloads children once if their resource IDs changed during loading", %{conn: conn} do
    Application.put_env(:pronotex, :dashboard_test_mode, :rotating_children)
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    assert_receive {:events, "a-1"}
    assert_receive {:events, "a-2"}
    refute_received {:events, _}
    refute has_element?(view, "#flash-error")
    assert has_element?(view, "#upcoming-events", "Réunion a-2")
    assert has_element?(view, "#lesson-days", "Maths a-2")
  end

  test "a persistently inaccessible child stays an error after one retry", %{conn: conn} do
    Application.put_env(:pronotex, :dashboard_test_mode, :inaccessible_child)
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    assert_receive {:events, "a"}
    assert_receive {:events, "a"}
    refute_received {:events, _}
    assert has_element?(view, "#flash-error", "Cet enfant")
  end

  test "upcoming events load with agenda and stay independent of the selected week", %{conn: conn} do
    {:ok, view, _} = live(conn, "/alice?week=2026-09-21")
    render_async(view)
    assert has_element?(view, "#upcoming-events", "Réunion a")
    assert has_element?(view, "#upcoming-events", "05/10/2026")
    refute has_element?(view, "#upcoming-events script")
    assert_receive {:events, "a"}
    refute_received {:events, _}
    view |> element(".child-picker-option[data-child-id]:not([aria-current])") |> render_click()
    render_async(view)
    assert has_element?(view, "#upcoming-events", "Réunion b")
    refute has_element?(view, "#upcoming-events", "Réunion a")
    assert_receive {:events, "b"}
    view |> element("#nav-devoirs") |> render_click()
    render_async(view)
    refute_received {:events, _}
  end

  test "upcoming event background follows today rather than the displayed week", %{conn: conn} do
    Application.put_env(:pronotex, :today, fn -> ~D[2026-10-02] end)
    {:ok, view, _} = live(conn, "/alice?week=2026-09-21")
    render_async(view)
    assert has_element?(view, "#upcoming-events article[data-imminent=true]", "Réunion a")

    Application.put_env(:pronotex, :today, fn -> ~D[2026-10-01] end)
    render_click(view, "refresh", %{})
    render_async(view)
    assert has_element?(view, "#upcoming-events article[data-imminent=false]", "Réunion a")
  end

  test "event errors and empty results do not hide lessons", %{conn: conn} do
    Application.put_env(:pronotex, :dashboard_test_mode, :events_failure)
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    assert has_element?(view, "#flash-error")
    assert has_element?(view, "#lesson-days", "Maths a")
    refute has_element?(view, "#no-events")
    Application.put_env(:pronotex, :dashboard_test_mode, :empty)
    view |> element("#retry-error") |> render_click()
    render_async(view)
    assert has_element?(view, "#no-events")
    refute has_element?(view, "#flash-error")
  end

  test "lesson highlighting follows start and end times without refetching", %{conn: conn} do
    Application.put_env(:pronotex, :now, fn -> ~N[2026-09-18 07:59:59] end)
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    assert has_element?(view, "#lesson-days article[data-state=upcoming]")
    assert_receive {:lessons, "a", _, _}
    Application.put_env(:pronotex, :now, fn -> ~N[2026-09-18 08:00:00] end)
    send(view.pid, :update_lesson_clock)
    assert has_element?(view, "#lesson-days article[data-state=current]", "En cours")
    Application.put_env(:pronotex, :now, fn -> ~N[2026-09-18 09:00:00] end)
    send(view.pid, :update_lesson_clock)
    assert has_element?(view, "#lesson-days article[data-state=past]")
    refute has_element?(view, "#lesson-days", "En cours")
    refute_received {:lessons, _, _, _}
  end

  test "canceled lessons highlight the current time slot while keeping their status", %{
    conn: conn
  } do
    Application.put_env(:pronotex, :dashboard_test_mode, :canceled)
    Application.put_env(:pronotex, :now, fn -> ~N[2026-09-18 08:30:00] end)
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    assert has_element?(view, "#lesson-days article[data-state=current]", "Annulé")

    Application.put_env(:pronotex, :now, fn -> ~N[2026-09-18 09:00:00] end)
    send(view.pid, :update_lesson_clock)
    refute has_element?(view, "#lesson-days article[data-state=current]")
    assert has_element?(view, "#lesson-days article[data-state=past]", "Annulé")
  end

  test "highlight moves from lesson to pause to lunch and back without refetching", %{conn: conn} do
    Application.put_env(:pronotex, :dashboard_test_mode, :pauses)
    Application.put_env(:pronotex, :now, fn -> ~N[2026-09-18 11:14:59] end)
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    assert_receive {:lessons, "a", _, _}
    assert has_element?(view, "#lesson-days article[data-state=current]")
    refute has_element?(view, ".agenda-pause[data-state=current]")

    for {time, label} <- [{~N[2026-09-18 11:15:00], "Pause"}, {~N[2026-09-18 12:10:00], "Repas"}] do
      Application.put_env(:pronotex, :now, fn -> time end)
      send(view.pid, :update_lesson_clock)
      assert has_element?(view, ".agenda-pause[data-state=current]", label)
      assert has_element?(view, ".agenda-pause[data-state=current]", "En cours")

      assert length(
               view
               |> element("#lesson-days")
               |> render()
               |> Floki.parse_fragment!()
               |> Floki.find("[data-state=current]")
             ) == 1

      refute has_element?(view, "#lesson-days article[data-state=current]")
    end

    Application.put_env(:pronotex, :now, fn -> ~N[2026-09-18 12:55:00] end)
    send(view.pid, :update_lesson_clock)
    refute has_element?(view, ".agenda-pause[data-state=current]")
    assert has_element?(view, "#lesson-days article[data-state=current]")
    refute_received {:lessons, _, _, _}
  end

  test "past lesson notes open separately and return to the same agenda", %{conn: conn} do
    Application.put_env(:pronotex, :dashboard_test_mode, :lesson_content)
    Application.put_env(:pronotex, :now, fn -> ~N[2026-09-18 12:00:00] end)
    {:ok, view, _} = live(conn, "/alice?week=2026-09-14")
    render_async(view)
    assert has_element?(view, "svg[aria-label='Contenu du cours']")
    assert has_element?(view, "svg[aria-label='Ressources du cours']")
    view |> element(".lesson-detail-link") |> render_click()
    assert has_element?(view, "#lesson-detail", "Comparer des fractions")

    assert view
           |> render()
           |> Floki.parse_document!()
           |> Floki.find(".lesson-content-text")
           |> Floki.text() == "Comparer des fractions"

    assert has_element?(view, "#lesson-detail h2", "Maths a")
    assert has_element?(view, "#agenda-content[hidden]")
    assert has_element?(view, "#lesson-detail a[href='https://example.org/exercice']")
    view |> element("#lesson-breadcrumb a", "Retour à l’agenda") |> render_click()
    refute has_element?(view, "#lesson-detail")
    assert has_element?(view, "#agenda-content:not([hidden])")
    assert has_element?(view, ".lesson-detail-link[href*='week=2026-09-14']")
  end

  test "future lessons do not expose content links", %{conn: conn} do
    Application.put_env(:pronotex, :dashboard_test_mode, :lesson_content)
    Application.put_env(:pronotex, :now, fn -> ~N[2026-09-18 07:00:00] end)
    {:ok, view, _} = live(conn, "/alice?week=2026-09-21")
    render_async(view)
    refute has_element?(view, ".lesson-detail-link")
    refute has_element?(view, "svg[aria-label='Contenu du cours']")
  end

  test "a detail URL cannot show a lesson outside the selected agenda", %{conn: conn} do
    Application.put_env(:pronotex, :dashboard_test_mode, :lesson_content)
    {:ok, view, _} = live(conn, "/alice?week=2026-09-14&lesson=unknown")
    render_async(view)
    assert has_element?(view, "#lesson-detail-empty")
    refute has_element?(view, "#lesson-detail article")
  end

  test "homework badge stays visible during navigation without leaking to another child", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    assert has_element?(view, "#homework-nav-badge", "1")
    Application.put_env(:pronotex, :dashboard_test_mode, :slow_homework)
    view |> element("#nav-notes") |> render_click()
    assert_receive {:homework_pending, task}
    assert has_element?(view, "#nav-devoirs[disabled] #homework-nav-badge", "1")
    send(task, :finish_homework)
    render_async(view)
    assert has_element?(view, "#homework-nav-badge", "1")
    render_click(view, "select-child", %{"id" => "b"})
    assert_receive {:homework_pending, other_task}
    refute has_element?(view, "#homework-nav-badge")
    send(other_task, :finish_homework)
    render_async(view)
  end

  test "homework toggle checks and unchecks only the selected child's task", %{conn: conn} do
    {:ok, view, _} = live(conn, "/alice/devoirs")
    render_async(view)
    assert has_element?(view, "#homework-toggle-task[aria-pressed=false]")
    assert has_element?(view, "#homework-nav-badge", "1")
    view |> element("#homework-toggle-task") |> render_click()
    render_async(view)
    assert_receive {:write_homework, "a", "task", true}
    assert has_element?(view, "#homework-toggle-task[aria-pressed=true]")
    refute has_element?(view, "#homework-nav-badge")
    view |> element("#homework-toggle-task") |> render_click()
    render_async(view)
    assert_receive {:write_homework, "a", "task", false}
    assert has_element?(view, "#homework-nav-badge", "1")
    assert has_element?(view, "#homework-toggle-task[aria-pressed=false]")
    render_click(view, "toggle-homework", %{"id" => "unknown"})
    refute_received {:write_homework, _, _, _}
  end

  test "parent write refusal keeps the confirmed status", %{conn: conn} do
    Application.put_env(:pronotex, :dashboard_test_mode, :write_failure)
    {:ok, view, _} = live(conn, "/alice/devoirs")
    render_async(view)
    view |> element("#homework-toggle-task") |> render_click()
    render_async(view)
    assert has_element?(view, "#flash-error", "compte élève")
    assert has_element?(view, "#homework-toggle-task[aria-pressed=false][disabled]")
    Application.delete_env(:pronotex, :dashboard_test_mode)
    view |> element("#retry-error") |> render_click()
    render_async(view)
    refute has_element?(view, "#flash-error")
    refute has_element?(view, "#homework-toggle-task[disabled]")
  end

  test "pending writes are not optimistic and cannot overwrite another child's page", %{
    conn: conn
  } do
    Application.put_env(:pronotex, :dashboard_test_mode, :slow_write)
    {:ok, view, _} = live(conn, "/alice/devoirs")
    render_async(view)
    view |> element("#homework-toggle-task") |> render_click()
    assert_receive {:write_pending, writer}
    assert has_element?(view, "#homework-toggle-task[aria-pressed=false][disabled]")
    render_click(view, "toggle-homework", %{"id" => "task"})
    assert_receive {:write_homework, "a", "task", true}
    refute_received {:write_homework, _, _, _}
    render_patch(view, "/basile/devoirs")
    send(writer, :finish_write)
    render_async(view)
    assert has_element?(view, "#homework-days", "Français b")
    assert has_element?(view, "#homework-toggle-task[aria-pressed=false]")
  end

  test "homework is read only when student credentials are absent", %{conn: conn} do
    Application.put_env(:pronotex, :dashboard_test_mode, :no_student)
    {:ok, view, _} = live(conn, "/alice/devoirs")
    render_async(view)
    refute has_element?(view, "#homework-toggle-task")
    render_click(view, "toggle-homework", %{"id" => "task"})
    refute_received {:write_homework, _, _, _}
  end
end
