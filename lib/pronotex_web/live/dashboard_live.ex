defmodule PronotexWeb.DashboardLive do
  use PronotexWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    today = today()
    if connected?(socket), do: Process.send_after(self(), :update_lesson_clock, 30_000)

    socket =
      socket
      |> assign(
        page_title: "Mon agenda",
        section: "agenda",
        grade_period: nil,
        grade_periods: [],
        grades_error: nil,
        grade_count: 0,
        average_count: 0,
        overall: nil,
        class_overall: nil,
        overall_out_of: nil,
        children: [],
        child: nil,
        selected_slug: nil,
        loaded_selection: nil,
        current_url: nil,
        week: today,
        mode: :today,
        today: today,
        now: now(),
        loading: true,
        error: nil,
        event_error: nil,
        event_count: 0,
        lesson_error: nil,
        homework_writable: false,
        homework_saving: nil,
        homework_save_error: nil,
        homework_error: nil,
        lesson_count: 0,
        menu_count: 0,
        menu_error: nil,
        homework_count: 0,
        homework_badge_count: 0,
        api: Application.get_env(:pronotex, :pronote_client, Pronotex.Pronote)
      )
      |> stream(:events, [])
      |> stream(:lesson_days, [])
      |> stream(:grades, [])
      |> stream(:averages, [])
      |> stream(:menu_days, [])
      |> stream(:homework_days, [])

    {:ok, socket}
  end

  @impl true
  def handle_info(:update_lesson_clock, socket) do
    Process.send_after(self(), :update_lesson_clock, 30_000)
    socket = assign(socket, :now, now())

    socket =
      Enum.reduce(socket.private[:lesson_days] || [], socket, fn day, socket ->
        stream_insert(socket, :lesson_days, day)
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_params(params, uri, socket) do
    today = today()
    {mode, week} = parse_selection(params["week"], today)
    slug = params["child"]

    section =
      case params["section"] do
        "devoirs" -> "devoirs"
        "notes" -> "notes"
        "menu" -> "cantine"
        _ -> "agenda"
      end

    period =
      case params["period"] do
        value when is_binary(value) -> if Regex.match?(~r/^[a-z0-9-]{1,80}$/, value), do: value
        _ -> nil
      end

    uri = URI.parse(uri)
    url = uri.path <> if(uri.query, do: "?" <> uri.query, else: "")
    child = Enum.find(socket.assigns.children, &(child_slug(&1) == slug))

    socket =
      assign(socket,
        week: week,
        mode: mode,
        section: section,
        grade_period: period,
        today: today,
        selected_slug: slug,
        current_url: url,
        page_title: page_title(child, slug, section),
        child: child
      )

    # The canonical URL patch after loading must not fetch the same data twice.
    if connected?(socket) and
         socket.assigns.loaded_selection != {slug, section, mode, week, period} do
      {:noreply, load(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(_event, _params, %{assigns: %{loading: true}} = socket),
    do: {:noreply, socket}

  def handle_event("toggle-homework", %{"id" => id}, socket) do
    task =
      (socket.private[:homework_days] || [])
      |> Enum.flat_map(& &1.entries)
      |> Enum.find(&(&1.id == id))

    if socket.assigns.section == "devoirs" and socket.assigns.homework_writable and
         is_nil(socket.assigns.homework_saving) and task do
      api = socket.assigns.api
      child_id = socket.assigns.child.id
      generation = socket.private[:homework_generation]

      socket =
        socket |> assign(homework_saving: id, homework_save_error: nil) |> restream_homework()

      {:noreply,
       start_async(socket, {:save_homework, generation}, fn ->
         api.set_homework_done(child_id, id, !task.done)
       end)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("grade-period", %{"period" => period}, socket) do
    if Enum.any?(socket.assigns.grade_periods, fn {_label, key} -> key == period end) do
      {:noreply, push_patch(socket, to: selection_url(socket, period: period))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("section", %{"section" => section}, socket)
      when section in ["agenda", "devoirs", "notes", "cantine"] do
    {:noreply, push_patch(socket, to: selection_url(socket, section: section))}
  end

  def handle_event("switch-child", _, %{assigns: %{children: children}} = socket)
      when length(children) < 2, do: {:noreply, socket}

  def handle_event("switch-child", _, socket) do
    children = socket.assigns.children
    index = Enum.find_index(children, &(&1.id == socket.assigns.child.id)) || 0
    child = Enum.at(children, rem(index + 1, length(children)))

    {:noreply, push_patch(socket, to: selection_url(socket, child: child))}
  end

  def handle_event("week", %{"direction" => direction}, socket)
      when direction in ["previous", "next"] do
    date = if socket.assigns.mode == :today, do: today(), else: socket.assigns.week
    monday = Date.add(date, 1 - Date.day_of_week(date))

    offset =
      case {socket.assigns.mode, direction} do
        {:today, "previous"} -> 0
        {_, "previous"} -> -7
        {_, "next"} -> 7
      end

    {:noreply,
     push_patch(socket,
       to: selection_url(socket, mode: :week, week: Date.add(monday, offset))
     )}
  end

  def handle_event("today", _, socket) do
    {:noreply, push_patch(socket, to: selection_url(socket, mode: :today, week: today()))}
  end

  def handle_event("refresh", _, socket) do
    current_date = today()
    socket = assign(socket, :today, current_date)

    socket =
      if socket.assigns.mode == :today, do: assign(socket, :week, current_date), else: socket

    {:noreply, load(socket)}
  end

  @impl true
  def handle_async(:load, {:ok, {:ok, result}}, socket) do
    socket =
      assign(socket,
        children: result.children,
        child: result.child,
        homework_badge_count: pending_count(result.urgent_homework),
        homework_writable: socket.assigns.api.homework_writable?(result.child),
        page_title: page_title(result.child, nil, socket.assigns.section),
        loading: false,
        error: nil
      )

    {:noreply,
     socket
     |> put_private(:urgent_homework, result.urgent_homework)
     |> apply_result(:events, result.events)
     |> apply_result(:lessons, result.lessons)
     |> apply_result(:homework, result.homework)
     |> apply_result(:menus, result.menus)
     |> apply_result(:grades, result.grades)
     |> mark_loaded()
     |> canonicalize()}
  end

  def handle_async(:load, {:ok, {:error, error}}, socket),
    do: {:noreply, assign(socket, loading: false, error: message(error))}

  def handle_async(:load, {:exit, _reason}, socket),
    do:
      {:noreply,
       assign(socket, loading: false, error: "Le chargement a échoué. Réessayez dans un instant.")}

  def handle_async({:save_homework, generation}, result, socket) do
    if generation == socket.private[:homework_generation] do
      socket = assign(socket, :homework_saving, nil)

      socket =
        case result do
          {:ok, {:ok, tasks}} ->
            socket |> update_homework_badge(tasks) |> apply_result(:homework, {:ok, tasks})

          {:ok, {:error, error}} ->
            text =
              case error do
                %Pronotex.Pronote.Error{reason: :forbidden} ->
                  "Pronote refuse cette modification avec le compte élève."

                %Pronotex.Pronote.Error{reason: reason}
                when reason in [:homework_unconfirmed, :stale_homework] ->
                  message(error)

                _ ->
                  message(error) <> " Rechargez les devoirs avant de réessayer."
              end

            homework_save_failed(socket, text)

          {:exit, _} ->
            homework_save_failed(
              socket,
              "Impossible de confirmer le changement. Rechargez les devoirs pour vérifier."
            )
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp homework_save_failed(socket, text) do
    socket
    |> assign(:homework_save_error, text)
    |> put_flash(:error, text)
    |> restream_homework()
  end

  defp restream_homework(socket) do
    Enum.reduce(socket.private[:homework_days] || [], socket, fn day, socket ->
      stream_insert(socket, :homework_days, day)
    end)
  end

  defp load(socket) do
    period = socket.assigns.grade_period
    section = socket.assigns.section
    api = socket.assigns.api
    selected_slug = socket.assigns.selected_slug
    mode = socket.assigns.mode
    from = socket.assigns.week
    to = Date.add(from, 6)
    today = socket.assigns.today

    socket
    |> clear_flash(:error)
    |> assign(
      loading: true,
      loaded_selection: nil,
      grades_error: nil,
      grade_count: 0,
      average_count: 0,
      overall: nil,
      class_overall: nil,
      overall_out_of: nil,
      error: nil,
      event_error: nil,
      event_count: 0,
      lesson_error: nil,
      homework_saving: nil,
      homework_save_error: nil,
      homework_error: nil,
      lesson_count: 0,
      menu_count: 0,
      menu_error: nil,
      homework_count: 0,
      homework_badge_count: 0
    )
    |> stream(:events, [], reset: true)
    |> stream(:grades, [], reset: true)
    |> stream(:averages, [], reset: true)
    |> stream(:menu_days, [], reset: true)
    |> put_private(:lesson_days, [])
    |> stream(:lesson_days, [], reset: true)
    |> put_private(:homework_generation, make_ref())
    |> put_private(:homework_days, [])
    |> stream(:homework_days, [], reset: true)
    |> start_async(:load, fn ->
      with {:ok, children} <- api.children(),
           child when not is_nil(child) <-
             Enum.find(children, &(child_slug(&1) == selected_slug)) || List.first(children) do
        urgent_homework =
          case api.homework(child.id, today, Pronotex.Pronote.Homework.urgent_until(today)) do
            {:ok, tasks} ->
              Enum.filter(
                tasks,
                &(Date.compare(&1.date, today) != :lt and
                    Date.compare(&1.date, Pronotex.Pronote.Homework.urgent_until(today)) != :gt)
              )

            _ ->
              []
          end

        {:ok,
         %{
           urgent_homework: urgent_homework,
           children: children,
           child: child,
           week: from,
           mode: mode,
           events: if(section == "agenda", do: api.events(child.id), else: {:ok, []}),
           lessons: if(section == "agenda", do: api.lessons(child.id, from, to), else: {:ok, []}),
           homework:
             if(section == "devoirs", do: api.homework(child.id, from, to), else: {:ok, []}),
           menus: if(section == "cantine", do: api.menus(child.id, from, to), else: {:ok, []}),
           grades: if(section == "notes", do: api.grades(child.id, period), else: :skip)
         }}
      else
        nil -> {:error, "Aucun enfant accessible sur ce compte."}
        {:error, error} -> {:error, error}
      end
    end)
  end

  defp pending_count(tasks), do: Enum.count(tasks, &(!&1.done))

  defp update_homework_badge(socket, tasks) do
    statuses = Map.new(tasks, &{{&1.id, &1.date}, &1.done})

    urgent =
      Enum.map(socket.private[:urgent_homework] || [], fn task ->
        %{task | done: Map.get(statuses, {task.id, task.date}, task.done)}
      end)

    socket
    |> put_private(:urgent_homework, urgent)
    |> assign(:homework_badge_count, pending_count(urgent))
  end

  defp now do
    Application.get_env(:pronotex, :now, fn ->
      {date, time} = :calendar.local_time()
      NaiveDateTime.new!(Date.from_erl!(date), Time.from_erl!(time))
    end).()
  end

  defp lesson_state(lesson, now) do
    cond do
      NaiveDateTime.compare(now, lesson.end) != :lt -> "past"
      !lesson.canceled and NaiveDateTime.compare(now, lesson.start) != :lt -> "current"
      true -> "upcoming"
    end
  end

  defp today do
    # This is a local app: use the host's local calendar date, not UTC near midnight.
    Application.get_env(:pronotex, :today, fn ->
      {date, _time} = :calendar.local_time()
      Date.from_erl!(date)
    end).()
  end

  defp parse_selection(value, today) do
    case is_binary(value) && Date.from_iso8601(value) do
      {:ok, date} -> {:week, Date.add(date, 1 - Date.day_of_week(date))}
      _ -> {:today, today}
    end
  end

  defp page_title(child, slug, section) do
    label =
      Map.fetch!(
        %{"agenda" => "Agenda", "devoirs" => "Devoirs", "notes" => "Notes", "cantine" => "Menu"},
        section
      )

    name =
      cond do
        child -> first_name(child)
        is_binary(slug) -> String.capitalize(slug)
        true -> nil
      end

    if name, do: "#{name} - #{label}", else: label
  end

  defp child_slug(child) do
    child |> first_name() |> String.trim() |> String.downcase() |> String.replace(~r/\s+/u, "-")
  end

  defp selection_url(socket, overrides \\ []) do
    child = Keyword.get(overrides, :child, socket.assigns.child)
    section = Keyword.get(overrides, :section, socket.assigns.section)
    mode = Keyword.get(overrides, :mode, socket.assigns.mode)
    week = Keyword.get(overrides, :week, socket.assigns.week)
    period = Keyword.get(overrides, :period, socket.assigns.grade_period)
    base = if child, do: ~p"/#{child_slug(child)}", else: ~p"/"

    path =
      case section do
        "devoirs" when not is_nil(child) -> ~p"/#{child_slug(child)}/devoirs"
        "notes" when not is_nil(child) -> ~p"/#{child_slug(child)}/notes"
        "cantine" when not is_nil(child) -> ~p"/#{child_slug(child)}/menu"
        _ -> base
      end

    query = if mode == :week, do: [{"week", Date.to_iso8601(week)}], else: []
    query = if period, do: query ++ [{"period", period}], else: query
    path <> if(query == [], do: "", else: "?" <> URI.encode_query(query))
  end

  defp mark_loaded(socket) do
    a = socket.assigns

    assign(
      socket,
      :loaded_selection,
      {child_slug(a.child), a.section, a.mode, a.week, a.grade_period}
    )
  end

  defp canonicalize(socket) do
    url = selection_url(socket)

    if socket.assigns.current_url == url,
      do: socket,
      else: push_patch(socket, to: url, replace: true)
  end

  defp apply_result(socket, :events, {:ok, events}) do
    socket
    |> assign(event_count: length(events), event_error: nil)
    |> stream(:events, events, reset: true)
  end

  defp apply_result(socket, :events, {:error, error}),
    do: assign(socket, :event_error, message(error))

  defp apply_result(socket, :grades, :skip), do: socket

  defp apply_result(socket, :grades, {:error, error}),
    do: assign(socket, :grades_error, message(error))

  defp apply_result(socket, :grades, {:ok, report}) do
    socket
    |> assign(
      grade_period: Pronotex.Pronote.Grades.period_key(report.period),
      grade_periods: Enum.map(report.periods, &{&1, Pronotex.Pronote.Grades.period_key(&1)}),
      grade_count: length(report.grades),
      average_count: length(report.averages),
      overall: report.overall,
      class_overall: report.class_overall,
      overall_out_of: report.overall_out_of
    )
    |> stream(:grades, report.grades, reset: true)
    |> stream(:averages, report.averages, reset: true)
  end

  defp apply_result(socket, :menus, {:ok, menus}) do
    socket
    |> assign(menu_count: length(menus), menu_error: nil)
    |> stream(:menu_days, grouped(menus, & &1.date), reset: true)
  end

  defp apply_result(socket, :menus, {:error, %Pronotex.Pronote.Error{reason: :forbidden}}),
    do:
      assign(
        socket,
        :menu_error,
        "Les menus ne sont pas accessibles pour cet enfant dans Pronote."
      )

  defp apply_result(socket, :menus, {:error, error}),
    do: assign(socket, :menu_error, message(error))

  defp apply_result(socket, :lessons, {:ok, lessons}) do
    days =
      lessons
      |> grouped(&NaiveDateTime.to_date(&1.start))
      |> Enum.map(fn day -> %{day | entries: Pronotex.Agenda.entries(day.entries)} end)

    days =
      if socket.assigns.mode == :today and not Enum.any?(days, &(&1.date == socket.assigns.today)) do
        [
          %{id: Date.to_iso8601(socket.assigns.today), date: socket.assigns.today, entries: []}
          | days
        ]
      else
        days
      end

    socket
    |> assign(lesson_count: length(lessons), lesson_error: nil)
    |> assign(:now, now())
    |> put_private(:lesson_days, days)
    |> stream(:lesson_days, days, reset: true)
  end

  defp apply_result(socket, :homework, {:ok, homework}) do
    days = grouped(homework, & &1.date)

    socket
    |> assign(homework_count: length(homework), homework_error: nil)
    |> put_private(:homework_days, days)
    |> stream(:homework_days, days, reset: true)
  end

  defp apply_result(socket, :lessons, {:error, error}),
    do: assign(socket, :lesson_error, message(error))

  defp apply_result(socket, :homework, {:error, error}),
    do: assign(socket, :homework_error, message(error))

  defp mark(nil, _out_of), do: "Non disponible"

  defp mark(score, out_of) do
    case Float.parse(String.replace(score, ",", ".")) do
      {_, ""} when not is_nil(out_of) -> "#{score} / #{out_of}"
      _ -> score
    end
  end

  defp grouped(items, date_fun) do
    items
    |> Enum.group_by(date_fun)
    |> Enum.sort_by(&elem(&1, 0), Date)
    |> Enum.map(fn {date, entries} ->
      %{id: Date.to_iso8601(date), date: date, entries: entries}
    end)
  end

  defp message(%Pronotex.Pronote.Error{reason: :missing_credentials}),
    do: "Le compte Pronote n’est pas encore configuré."

  defp message(%Pronotex.Pronote.Error{reason: :additional_authentication_required}),
    do: "Pronote demande une vérification supplémentaire pour ce compte."

  defp message(%Pronotex.Pronote.Error{message: message}), do: message
  defp message(message) when is_binary(message), do: message
  defp message(_), do: "Impossible de charger les données pour le moment."

  defp event_schedule(event) do
    first = Calendar.strftime(event.start, "%d/%m/%Y")
    last = Calendar.strftime(event.end, "%d/%m/%Y")

    if first == last do
      "#{first} · #{clock(event.start)}–#{clock(event.end)}"
    else
      "Du #{first} à #{clock(event.start)} au #{last} à #{clock(event.end)}"
    end
  end

  defp compact_week(date) do
    last = Date.add(date, 6)
    months = ~w(janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.)

    start_label =
      if date.month == last.month,
        do: to_string(date.day),
        else: "#{date.day} #{Enum.at(months, date.month - 1)}"

    "#{start_label}–#{last.day} #{Enum.at(months, last.month - 1)}"
  end

  defp day_label(date) do
    day =
      Enum.at(~w(Lundi Mardi Mercredi Jeudi Vendredi Samedi Dimanche), Date.day_of_week(date) - 1)

    "#{day} #{Calendar.strftime(date, "%d/%m")}"
  end

  defp relative_day(date, today) do
    case Date.diff(date, today) do
      0 -> "Aujourd’hui"
      1 -> "Demain"
      _ -> day_label(date)
    end
  end

  defp due_label(date, today) do
    case Date.diff(date, today) do
      0 -> "Pour aujourd’hui"
      1 -> "Pour demain"
      _ -> "Pour " <> String.downcase(day_label(date))
    end
  end

  defp child_theme(_children, nil), do: "blue"
  defp child_theme(children, child), do: Pronotex.Family.theme(children, child)
  defp avatar_src(nil), do: nil
  defp avatar_src(child), do: Pronotex.Family.avatar(child)
  defp first_name(child), do: Pronotex.Family.first_name(child)

  defp clock(time), do: Calendar.strftime(time, "%H:%M")

  defp next_child(children, child) do
    Enum.find(children, &(&1.id != child.id))
  end
end
