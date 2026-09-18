defmodule PronotexWeb.DashboardLiveTest do
  use PronotexWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  test "dashboard opens without a session when PIN is disabled" do
    original = Pronotex.Auth.pin()
    on_exit(fn -> Application.put_env(:pronotex, :pin_code, original) end)
    Application.put_env(:pronotex, :pin_code, nil)
    {:ok, view, _} = live(build_conn(), "/alice")
    render_async(view)
    assert has_element?(view, "#lesson-days", "Maths a")
    view |> element("#nav-devoirs") |> render_click()
    render_async(view)
    assert has_element?(view, "#homework-days")
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
        :failure -> {:error, Pronotex.Pronote.Error.new(:network)}
        :no_children -> {:ok, []}
        _ -> {:ok, [%{id: "a", name: "Alice"}, %{id: "b", name: "Basile"}]}
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

  setup do
    keys = [:pronote_client, :dashboard_test_pid, :dashboard_test_mode, :today, :now]
    previous = Map.new(keys, &{&1, Application.fetch_env(:pronotex, &1)})
    Application.put_env(:pronotex, :today, fn -> ~D[2026-09-18] end)
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
    assert Date.diff(to, from) == 6
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
    assert has_element?(view, "#homework-error")
    refute has_element?(view, "#no-homework")
    view |> element("#nav-agenda") |> render_click()
    render_async(view)
    assert has_element?(view, "#lesson-days", "Maths a")
  end

  test "failed initialization can be retried", %{conn: conn} do
    Application.put_env(:pronotex, :dashboard_test_mode, :failure)
    {:ok, view, _} = live(conn, ~p"/")
    render_async(view)
    assert has_element?(view, "#page-error")
    refute has_element?(view, "#no-lessons")
    Application.delete_env(:pronotex, :dashboard_test_mode)
    view |> element("#retry") |> render_click()
    render_async(view)
    refute has_element?(view, "#page-error")
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
    assert_receive {:lessons, "a", ~D[2026-09-18], ~D[2026-09-24]}
    refute_received {:lessons, _, _, _}
  end

  test "today and week modes retain the child and support browser navigation", %{conn: conn} do
    {:ok, view, _} = live(conn, "/basile?week=2026-09-07")
    render_async(view)
    view |> element("#today-view") |> render_click()
    assert_patch(view, "/basile")
    render_async(view)
    assert_receive {:lessons, "b", ~D[2026-09-18], ~D[2026-09-24]}
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
    assert_receive {:lessons, "a", ~D[2026-09-18], ~D[2026-09-24]}
  end

  test "refresh rolls the today range forward after midnight", %{conn: conn} do
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    Application.put_env(:pronotex, :today, fn -> ~D[2026-09-19] end)
    render_click(view, "refresh", %{})
    render_async(view)
    assert_receive {:lessons, "a", ~D[2026-09-19], ~D[2026-09-25]}
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
    assert_receive {:lessons, "a", ~D[2026-09-17], ~D[2026-09-23]}
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
    assert has_element?(view, "#menu-error")
    Application.delete_env(:pronotex, :dashboard_test_mode)
    view |> element("#retry-menus") |> render_click()
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
    assert has_element?(view, "#grades-error")
    refute has_element?(view, "#no-grades")
    Application.delete_env(:pronotex, :dashboard_test_mode)
    view |> element("#retry-grades") |> render_click()
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
             "#dashboard-navigation #grade-period option[value=semester2][selected]"
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
    assert has_element?(reopened, "#grade-period option[value=semester2][selected]")
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
    assert has_element?(view, "#events-error")
    assert has_element?(view, "#lesson-days", "Maths a")
    refute has_element?(view, "#no-events")
    Application.put_env(:pronotex, :dashboard_test_mode, :empty)
    view |> element("#retry-events") |> render_click()
    render_async(view)
    assert has_element?(view, "#no-events")
    refute has_element?(view, "#events-error")
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

  test "canceled lessons are never highlighted as current", %{conn: conn} do
    Application.put_env(:pronotex, :dashboard_test_mode, :canceled)
    Application.put_env(:pronotex, :now, fn -> ~N[2026-09-18 08:30:00] end)
    {:ok, view, _} = live(conn, "/alice")
    render_async(view)
    refute has_element?(view, "#lesson-days article[data-state=current]")
    assert has_element?(view, "#lesson-days", "Annulé")
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
    view |> element("#reload-homework") |> render_click()
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
