defmodule PronotexWeb.DashboardLive do
  use PronotexWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    today = today()
    if connected?(socket), do: Process.send_after(self(), :update_lesson_clock, 30_000)
    if connected?(socket), do: Phoenix.PubSub.subscribe(Pronotex.PubSub, "pronote:refresh")

    socket =
      socket
      |> assign(
        page_title: "Mon agenda",
        section: "agenda",
        discussions: [],
        messages_loading: false,
        messages_error: nil,
        messages_available: false,
        messages_unread: 0,
        parent_messages_unread: 0,
        message_saving: nil,
        open_discussion: nil,
        agenda_panel: "timetable",
        grades_panel: "latest",
        grade_period: nil,
        grade_periods: [],
        grades_error: nil,
        grade_count: 0,
        average_count: 0,
        overall: nil,
        grade_trend: [],
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
        remaining_events: [],
        lesson_error: nil,
        homework_writable: false,
        homework_saving: nil,
        homework_save_error: nil,
        homework_error: nil,
        agenda_from: today,
        lesson_count: 0,
        lessons: [],
        open_lesson: nil,
        menu_count: 0,
        menu_error: nil,
        homework_count: 0,
        homework_badge_count: 0,
        homework_badge_cache: %{},
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
  def handle_info({:pronote_refreshed, account_id}, socket) do
    if socket.assigns.account.id == account_id and not socket.assigns.loading and
         is_nil(socket.assigns.message_saving) and is_nil(socket.assigns.homework_saving) do
      {:noreply, load(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:update_lesson_clock, socket) do
    Process.send_after(self(), :update_lesson_clock, 30_000)
    socket = assign(socket, :now, now())

    socket =
      Enum.reduce(socket.private[:lesson_days] || [], socket, fn day, socket ->
        stream_insert(socket, :lesson_days, day)
      end)

    if socket.assigns.section == "agenda" and socket.assigns.mode == :today and
         !socket.assigns.loading and
         socket.assigns.agenda_from != agenda_start(today(), socket.assigns.now) do
      handle_event("refresh", %{}, socket)
    else
      {:noreply, socket}
    end
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
        "reglages" -> "settings"
        "menu" -> "cantine"
        "messages" -> "messages"
        "parent-messages" when socket.assigns.account.role == :parent -> "parent-messages"
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
        open_lesson: if(section == "agenda", do: params["lesson"]),
        open_discussion: if(section in ["messages", "parent-messages"], do: params["discussion"]),
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

  def handle_event("agenda-panel", %{"panel" => panel}, socket)
      when panel in ["timetable", "events"] do
    {:noreply, assign(socket, :agenda_panel, panel)}
  end

  def handle_event("grades-panel", %{"panel" => panel}, socket)
      when panel in ["latest", "averages"] do
    {:noreply, assign(socket, :grades_panel, panel)}
  end

  def handle_event("mark-discussion", %{"id" => id}, socket) do
    discussion = Enum.find(socket.assigns.discussions, &(&1.id == id))

    if (socket.assigns.section in ["messages", "parent-messages"] and discussion) &&
         is_nil(socket.assigns.message_saving) && !socket.assigns.messages_loading &&
         (Map.get(discussion, :kind) != :information ||
            Map.get(discussion, :can_acknowledge, false)) do
      api = socket.assigns.api
      account = socket.assigns.account
      child_id = socket.assigns.child.id
      generation = socket.assigns.messages_generation
      parent_inbox = socket.assigns.section == "parent-messages"
      target_read = Map.get(discussion, :kind) == :information || discussion.unread > 0

      {:noreply,
       socket
       |> assign(:message_saving, id)
       |> start_async({:message_save, generation}, fn ->
         if parent_inbox do
           api_call(api, account, :set_parent_discussion_read, [id, target_read])
         else
           api_call(api, account, :set_discussion_read, [child_id, id, target_read])
         end
       end)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("show-more-events", _, socket) do
    {:noreply,
     socket
     |> stream(:events, socket.assigns.remaining_events)
     |> assign(:remaining_events, [])}
  end

  def handle_event("toggle-homework", %{"id" => id}, socket) do
    task =
      (socket.private[:homework_days] || [])
      |> Enum.flat_map(& &1.entries)
      |> Enum.find(&(&1.id == id))

    if socket.assigns.section == "devoirs" and socket.assigns.homework_writable and
         is_nil(socket.assigns.homework_saving) and task do
      api = socket.assigns.api
      account = socket.assigns.account
      child_id = socket.assigns.child.id
      generation = socket.private[:homework_generation]

      socket =
        socket |> assign(homework_saving: id, homework_save_error: nil) |> restream_homework()

      {:noreply,
       start_async(socket, {:save_homework, generation}, fn ->
         api_call(api, account, :set_homework_done, [child_id, id, !task.done])
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
      when section in [
             "agenda",
             "devoirs",
             "notes",
             "cantine",
             "messages",
             "parent-messages",
             "settings"
           ] do
    {:noreply, push_patch(socket, to: selection_url(socket, section: section))}
  end

  def handle_event("select-child", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.children, &(&1.id == id)) do
      nil -> {:noreply, socket}
      child -> {:noreply, push_patch(socket, to: selection_url(socket, child: child))}
    end
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
    if socket.assigns.api == Pronotex.Pronote do
      api_call(socket.assigns.api, socket.assigns.account, :clear_cache, [])
    end

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
        homework_writable: writable?(socket.assigns.api, socket.assigns.account, result.child),
        page_title: page_title(result.child, nil, socket.assigns.section),
        loading: false,
        error: nil
      )

    {:noreply,
     socket
     |> cache_homework_badge(pending_count(result.urgent_homework))
     |> put_private(:urgent_homework, result.urgent_homework)
     |> apply_result(:events, result.events)
     |> apply_result(:lessons, result.lessons)
     |> apply_result(:homework, result.homework)
     |> apply_result(:menus, result.menus)
     |> apply_result(:grades, result.grades)
     |> flash_load_errors()
     |> mark_loaded()
     |> canonicalize()
     |> load_messages()}
  end

  def handle_async(:load, {:ok, {:error, error}}, socket),
    do: {:noreply, socket |> assign(loading: false, error: message(error)) |> flash_load_errors()}

  def handle_async(:load, {:exit, _reason}, socket),
    do:
      {:noreply,
       socket
       |> assign(loading: false, error: "Le chargement a échoué. Réessayez dans un instant.")
       |> flash_load_errors()}

  def handle_async({kind, generation}, result, socket)
      when kind in [:messages_load, :message_save] do
    if generation == socket.assigns.messages_generation do
      socket = assign(socket, messages_loading: false, message_saving: nil)

      case result do
        {:ok, {:ok, discussions}} ->
          {:noreply,
           socket
           |> assign(discussions: discussions, messages_error: nil)
           |> assign(
             if(socket.assigns.section == "parent-messages",
               do: :parent_messages_unread,
               else: :messages_unread
             ),
             Enum.sum(Enum.map(discussions, & &1.unread))
           )}

        _ ->
          text =
            case result do
              {:ok, {:error, error}} -> message(error)
              _ -> "Impossible de charger les messages. Réessayez dans un instant."
            end

          {:noreply, socket |> assign(messages_error: text) |> put_flash(:error, text)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_async({:other_inbox_count, generation}, {:ok, {key, {:ok, discussions}}}, socket) do
    if generation == socket.assigns.messages_generation do
      {:noreply, assign(socket, key, Enum.sum(Enum.map(discussions, & &1.unread)))}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:other_inbox_count, _}, _, socket), do: {:noreply, socket}

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
    account = socket.assigns.account
    selected_slug = socket.assigns.selected_slug
    mode = socket.assigns.mode
    from = socket.assigns.week
    to = Date.add(from, 6)

    {lessons_from, lessons_to} =
      if mode == :today do
        start = agenda_start(from, now())
        {start, Date.add(Date.beginning_of_week(start), 4)}
      else
        {from, to}
      end

    today = socket.assigns.today

    socket
    |> clear_flash(:error)
    |> assign(
      loading: true,
      agenda_from: lessons_from,
      messages_generation: make_ref(),
      discussions: [],
      messages_unread: 0,
      parent_messages_unread: 0,
      messages_error: nil,
      messages_loading: false,
      messages_available: false,
      message_saving: nil,
      loaded_selection: nil,
      grades_error: nil,
      grade_count: 0,
      average_count: 0,
      overall: nil,
      grade_trend: [],
      class_overall: nil,
      overall_out_of: nil,
      error: nil,
      event_error: nil,
      event_count: 0,
      remaining_events: [],
      lesson_error: nil,
      homework_saving: nil,
      homework_save_error: nil,
      homework_error: nil,
      lesson_count: 0,
      lessons: [],
      menu_count: 0,
      menu_error: nil,
      homework_count: 0,
      homework_badge_count:
        Map.get(socket.assigns.homework_badge_cache, {selected_slug, today}, 0)
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
      read = fn ->
        with {:ok, children} <- api_call(api, account, :children, []),
             child when not is_nil(child) <-
               Enum.find(children, &(child_slug(&1) == selected_slug)) || List.first(children) do
          urgent_homework =
            case api_call(api, account, :homework, [
                   child.id,
                   today,
                   Pronotex.Pronote.Homework.urgent_until(today)
                 ]) do
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
             events:
               if(section == "agenda",
                 do: api_call(api, account, :events, [child.id]),
                 else: {:ok, []}
               ),
             lessons:
               if(section == "agenda",
                 do: api_call(api, account, :lessons, [child.id, lessons_from, lessons_to]),
                 else: {:ok, []}
               ),
             homework:
               if(section == "devoirs",
                 do: api_call(api, account, :homework, [child.id, from, to]),
                 else: {:ok, []}
               ),
             menus:
               if(section == "cantine",
                 do: api_call(api, account, :menus, [child.id, from, to]),
                 else: {:ok, []}
               ),
             grades:
               if(section == "notes",
                 do: api_call(api, account, :grades, [child.id, period]),
                 else: :skip
               )
           }}
        else
          nil -> {:error, "Aucun enfant accessible sur ce compte."}
          {:error, error} -> {:error, error}
        end
      end

      read_with_fresh_children(read)
    end)
  end

  # PRONOTE child resource IDs can change when its session is renewed mid-load.
  # Repeat the complete read once so every request uses the refreshed child list.
  defp read_with_fresh_children(read) do
    result = read.()

    stale_children? =
      case result do
        {:ok, data} ->
          Enum.any?([:events, :lessons, :homework, :menus, :grades], fn key ->
            match?({:error, %Pronotex.Pronote.Error{reason: :child_not_found}}, data[key])
          end)

        _ ->
          false
      end

    if stale_children?, do: read.(), else: result
  end

  defp api_call(Pronotex.Pronote, account, operation, args) do
    server = Pronotex.Pronote.Session.for_account(account.id)
    apply(Pronotex.Pronote, operation, args ++ [server])
  end

  defp api_call(api, _account, operation, args), do: apply(api, operation, args)

  defp writable?(api, account, child),
    do: account.role == :child or api.homework_writable?(child)

  defp load_messages(socket) do
    account = socket.assigns.account
    api = socket.assigns.api
    child_id = socket.assigns.child.id
    parent_inbox = socket.assigns.section == "parent-messages"
    child_available = writable?(api, account, socket.assigns.child)
    available = if parent_inbox, do: account.role == :parent, else: child_available
    generation = socket.assigns.messages_generation
    socket = assign(socket, :messages_available, available)

    socket =
      if available do
        socket
        |> assign(:messages_loading, true)
        |> start_async({:messages_load, generation}, fn ->
          if parent_inbox,
            do: api_call(api, account, :parent_discussions, []),
            else: api_call(api, account, :discussions, [child_id])
        end)
      else
        socket
      end

    if account.role == :parent and (not parent_inbox or child_available) do
      start_async(socket, {:other_inbox_count, generation}, fn ->
        result =
          if parent_inbox,
            do: api_call(api, account, :discussions, [child_id]),
            else: api_call(api, account, :parent_discussions, [])

        key = if parent_inbox, do: :messages_unread, else: :parent_messages_unread
        {key, result}
      end)
    else
      socket
    end
  end

  defp flash_load_errors(socket) do
    errors =
      [:error, :event_error, :lesson_error, :homework_error, :menu_error, :grades_error]
      |> Enum.map(&socket.assigns[&1])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case errors do
      [] -> clear_flash(socket, :error)
      errors -> put_flash(socket, :error, Enum.join(errors, "\n"))
    end
  end

  defp cache_homework_badge(socket, count) do
    key = {child_slug(socket.assigns.child), socket.assigns.today}

    assign(socket,
      homework_badge_count: count,
      homework_badge_cache: Map.put(socket.assigns.homework_badge_cache, key, count)
    )
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
    |> cache_homework_badge(pending_count(urgent))
  end

  defp agenda_start(date, clock) do
    date =
      if Time.compare(NaiveDateTime.to_time(clock), ~T[18:00:00]) != :lt,
        do: Date.add(date, 1),
        else: date

    if Date.day_of_week(date) > 5, do: Date.add(Date.end_of_week(date), 1), else: date
  end

  defp now do
    Application.get_env(:pronotex, :now, fn ->
      {date, time} = :calendar.local_time()
      NaiveDateTime.new!(Date.from_erl!(date), Time.from_erl!(time))
    end).()
  end

  defp agenda_state(entry, now) do
    cond do
      NaiveDateTime.compare(now, entry.end) != :lt ->
        "past"

      NaiveDateTime.compare(now, entry.start) != :lt ->
        "current"

      true ->
        "upcoming"
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
        %{
          "agenda" => "Agenda",
          "devoirs" => "Devoirs",
          "notes" => "Notes",
          "settings" => "Réglages",
          "cantine" => "Menu",
          "messages" => "Messages",
          "parent-messages" => "Mes messages"
        },
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

    discussion =
      Keyword.get(
        overrides,
        :discussion,
        if(Keyword.has_key?(overrides, :child) or Keyword.has_key?(overrides, :section),
          do: nil,
          else: socket.assigns.open_discussion
        )
      )

    base = if child, do: ~p"/#{child_slug(child)}", else: ~p"/"

    path =
      case section do
        "devoirs" when not is_nil(child) ->
          ~p"/#{child_slug(child)}/devoirs"

        "settings" when not is_nil(child) ->
          ~p"/#{child_slug(child)}/reglages"

        "notes" when not is_nil(child) ->
          ~p"/#{child_slug(child)}/notes"

        inbox when inbox in ["messages", "parent-messages"] and not is_nil(child) ->
          if discussion,
            do: ~p"/#{child_slug(child)}/#{inbox}/#{discussion}",
            else: ~p"/#{child_slug(child)}/#{inbox}"

        "cantine" when not is_nil(child) ->
          ~p"/#{child_slug(child)}/menu"

        _ ->
          base
      end

    query = if mode == :week, do: [{"week", Date.to_iso8601(week)}], else: []
    query = if period, do: query ++ [{"period", period}], else: query
    lesson = if overrides == [], do: socket.assigns.open_lesson
    query = if section == "agenda" and lesson, do: query ++ [{"lesson", lesson}], else: query
    path <> if(query == [], do: "", else: "?" <> URI.encode_query(query))
  end

  defp lesson_key(lesson) do
    :crypto.hash(:sha256, lesson.id <> NaiveDateTime.to_iso8601(lesson.start))
    |> Base.url_encode64(padding: false)
  end

  defp lesson_url(url, key) do
    uri = URI.parse(url)
    query = URI.decode_query(uri.query || "") |> Map.put("lesson", key)
    URI.to_string(%{uri | query: URI.encode_query(query)})
  end

  defp agenda_url(url) do
    uri = URI.parse(url)
    query = URI.decode_query(uri.query || "") |> Map.delete("lesson")
    URI.to_string(%{uri | query: if(map_size(query) > 0, do: URI.encode_query(query))})
  end

  defp lesson_notes?(lesson),
    do: Enum.any?(Map.get(lesson, :contents, []), &(&1.title != "" or &1.description != ""))

  defp lesson_resources?(lesson),
    do: Enum.any?(Map.get(lesson, :contents, []), &(&1.resources != []))

  defp lesson_details?(lesson, now),
    do: NaiveDateTime.compare(lesson.end, now) != :gt and Map.get(lesson, :contents, []) != []

  defp discussion_url(slug, mode, week, period, discussion, inbox) do
    path = if discussion, do: ~p"/#{slug}/#{inbox}/#{discussion}", else: ~p"/#{slug}/#{inbox}"
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
    |> assign(
      event_count: length(events),
      event_error: nil,
      remaining_events: Enum.drop(events, 8)
    )
    |> stream(:events, Enum.take(events, 8), reset: true)
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
      grade_trend: Pronotex.Pronote.GradeTrend.points(Map.get(report, :average_history, [])),
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
      if socket.assigns.mode == :today and socket.assigns.agenda_from == socket.assigns.today and
           not Enum.any?(days, &(&1.date == socket.assigns.today)) do
        [
          %{id: Date.to_iso8601(socket.assigns.today), date: socket.assigns.today, entries: []}
          | days
        ]
      else
        days
      end

    socket
    |> assign(lesson_count: length(lessons), lesson_error: nil, lessons: lessons)
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

  defp communication_date(value) when is_binary(value) and value != "" do
    date = Pronotex.Pronote.Lesson.datetime(value)
    label = date |> NaiveDateTime.to_date() |> day_label() |> String.downcase()

    if String.contains?(value, " "),
      do: label <> Calendar.strftime(date, " à %Hh%M"),
      else: label
  rescue
    _ in [Pronotex.Pronote.Error, ArgumentError] -> value
  end

  defp communication_date(_), do: ""

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

  defp messages_label(%{role: :parent, label: name}, _child, "parent-messages"),
    do: "Messages " <> name

  defp messages_label(%{role: :parent}, child, "messages") when not is_nil(child),
    do: "Messages " <> first_name(child)

  defp messages_label(_account, _child, _section), do: "Messages"

  defp first_name(child), do: Pronotex.Family.first_name(child)

  defp clock(time), do: Calendar.strftime(time, "%H:%M")
end
