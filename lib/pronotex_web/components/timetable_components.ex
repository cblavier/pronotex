defmodule PronotexWeb.TimetableComponents do
  use Phoenix.Component
  import PronotexWeb.CoreComponents

  attr :lessons, :list, required: true
  attr :monday, :any, required: true
  attr :loading, :boolean, required: true
  attr :error, :any, default: nil
  attr :warning, :any, default: nil
  attr :today, :any, required: true
  attr :cycle, :string, default: nil

  def week_timetable(assigns) do
    days = for offset <- 0..4, do: Date.add(assigns.monday, offset)

    lessons =
      if assigns.loading,
        do: Enum.map(assigns.lessons, &project_to_week(&1, assigns.monday)),
        else: assigns.lessons

    lessons = Enum.filter(lessons, &(NaiveDateTime.to_date(&1.start) in days))
    first = min(8 * 60, Enum.min(Enum.map(assigns.lessons, &minutes(&1.start)), fn -> 8 * 60 end))
    last = max(17 * 60, Enum.max(Enum.map(assigns.lessons, &minutes(&1.end)), fn -> 17 * 60 end))
    first = div(first, 60) * 60
    last = div(last + 59, 60) * 60
    entries = if assigns.error, do: [], else: lessons
    assigns = assign(assigns, days: days, entries: entries, first: first, last: last)

    ~H"""
    <dialog
      id="week-overview"
      phx-hook="WeekOverview"
      class="week-overview"
      aria-labelledby="week-overview-title"
    >
      <div class="week-overview-surface" tabindex="-1" autofocus>
        <header class="week-overview-header lg:hidden">
          <button type="button" phx-click="close-week-overview" class="lesson-back-link">
            <.icon name="hero-chevron-left" class="size-4" /> Retour à l’agenda
          </button>
          <.week_selector
            id="overview-date-navigation"
            label_id="week-overview-title"
            week={@monday}
            cycle={@cycle}
            show_cycle
            prefix="overview-"
            week_event="overview-week"
            today_event="overview-today"
            loading={@loading}
            today_active={@monday == timetable_today(@today)}
          />
        </header>
        <p :if={@warning} role="status" class="text-sm">{@warning}</p>
        <div class="week-grid" aria-busy={to_string(@loading)}>
          <p :if={@loading} role="status" class={if @entries == [], do: "week-empty", else: "sr-only"}>
            Chargement de la semaine…
          </p>
          <div :if={@error} role="alert" class="week-empty">
            <p>{@error}</p>
            <button type="button" phx-click="open-week-overview" class="btn btn-sm">Réessayer</button>
          </div>
          <div class="week-hours" aria-hidden="true">
            <span
              :for={minute <- @first..(@last - 1)//60}
              style={"top: #{100 * (minute - @first) / (@last - @first)}%"}
            >
              {div(minute, 60)}h
            </span>
          </div>
          <section
            :for={date <- @days}
            id={"week-column-#{Date.day_of_week(date)}"}
            class="week-column"
            aria-label={day_name(date)}
          >
            <h3>{day_name(date)} <span>{Calendar.strftime(date, "%d/%m")}</span></h3>
            <div
              class="week-column-body"
              style={"grid-template-rows: repeat(#{@last - @first}, minmax(0, 1fr)); --hour-height: #{6000 / (@last - @first)}%"}
            >
              <article
                :for={{lesson, lane, lanes} <- positioned(@entries, date)}
                id={lesson_dom_id(lesson)}
                class={[
                  "week-lesson",
                  lesson.canceled && "week-lesson-canceled",
                  Map.get(lesson, :inactive_cycle) && "week-lesson-inactive"
                ]}
                data-inactive-cycle={Map.get(lesson, :inactive_cycle)}
                title={
                  if Map.get(lesson, :reference_date),
                    do:
                      "Autre cycle · cours du #{Calendar.strftime(lesson.reference_date, "%d/%m/%Y")}"
                }
                style={"top: #{100 * (minutes(lesson.start) - @first) / (@last - @first)}%; height: #{100 * (minutes(lesson.end) - minutes(lesson.start)) / (@last - @first)}%; left: #{100 * lane / lanes}%; width: #{100 / lanes}%; --subject-color: #{lesson.color || "#94a3b8"}"}
                aria-label={"#{lesson.subject || "Cours"}, #{Calendar.strftime(lesson.start, "%H:%M")}–#{Calendar.strftime(lesson.end, "%H:%M")}"}
              >
                <span class="week-subject week-subject-short" title={lesson.subject || "Cours"}>
                  {Map.get(lesson, :display_subject, short_subject(lesson.subject))}
                </span>
                <span class="week-subject week-subject-full" title={lesson.subject || "Cours"}>
                  {lesson.subject || "Cours"}
                </span>
                <div :if={!Map.get(lesson, :inactive_cycle)} class="week-badges">
                  <.lesson_badges lesson={lesson} />
                </div>
                <div
                  :if={lesson.teachers != [] || lesson.classrooms != []}
                  class="week-lesson-details text-base-content/55"
                >
                  <p
                    :if={lesson.teachers != []}
                    class="week-teacher"
                    title={Enum.join(lesson.teachers, ", ")}
                  >
                    {Enum.join(lesson.teachers, ", ")}
                  </p>
                  <p
                    :if={lesson.classrooms != []}
                    class="week-room"
                    title={Enum.join(lesson.classrooms, ", ")}
                  >
                    {Enum.join(lesson.classrooms, ", ")}
                  </p>
                </div>
              </article>
            </div>
          </section>
          <p :if={!@loading && !@error && @entries == []} class="week-empty">
            Aucun cours cette semaine.
          </p>
        </div>
      </div>
    </dialog>
    """
  end

  def timetable_today(date) do
    monday = Date.beginning_of_week(date)
    if Date.day_of_week(date) in [6, 7], do: Date.add(monday, 7), else: monday
  end

  defp project_to_week(lesson, monday) do
    previous_monday = lesson.start |> NaiveDateTime.to_date() |> Date.beginning_of_week()
    seconds = Date.diff(monday, previous_monday) * 86_400

    %{
      lesson
      | start: NaiveDateTime.add(lesson.start, seconds),
        end: NaiveDateTime.add(lesson.end, seconds)
    }
  end

  # Dates and API identifiers change between weeks, but recurring slots keep their DOM node.
  defp lesson_dom_id(lesson) do
    slot = {
      Date.day_of_week(NaiveDateTime.to_date(lesson.start)),
      minutes(lesson.start),
      minutes(lesson.end),
      lesson.subject,
      Map.get(lesson, :inactive_cycle)
    }

    "week-lesson-" <>
      Base.url_encode64(:crypto.hash(:sha256, :erlang.term_to_binary(slot)), padding: false)
  end

  defp short_subject(subject) do
    subject =
      if is_binary(subject),
        do: Regex.replace(~r/^(ANGLAIS|ESPAGNOL) LV[0-9]+$/, subject, "\\1"),
        else: subject

    Map.get(
      %{
        "ED.PHYSIQUE & SPORT" => "EPS",
        "ED.PHYSIQUE & SPORT." => "EPS",
        "MATHEMATIQUES" => "MATHS",
        "SCIENCES VIE & TERRE" => "SVT",
        "LCA LATIN" => "LATIN",
        "HISTOIRE-GEOGRAPHIE" => "HISTOIRE-GEO",
        "EDUCATION-MUSICALE" => "MUSIQUE",
        "EDUCATION MUSICALE" => "MUSIQUE"
      },
      subject,
      subject || "Cours"
    )
  end

  # Resolve replacements separately for each cycle before allocating its column.
  defp positioned(lessons, date) do
    lessons
    |> Enum.filter(&(NaiveDateTime.to_date(&1.start) == date))
    |> Enum.group_by(&Map.get(&1, :inactive_cycle))
    |> Enum.flat_map(fn {_cycle, entries} ->
      entries
      |> Pronotex.Agenda.entries()
      |> overlapping_groups()
      |> Enum.map(&merge_simultaneous/1)
    end)
    |> overlapping_groups()
    |> Enum.flat_map(fn group ->
      cycles = group |> Enum.map(&Map.get(&1, :inactive_cycle)) |> Enum.uniq() |> Enum.sort()

      Enum.map(group, fn lesson ->
        lane = Enum.find_index(cycles, &(&1 == Map.get(lesson, :inactive_cycle)))
        {lesson, lane, length(cycles)}
      end)
    end)
  end

  defp overlapping_groups(lessons) do
    lessons
    |> Enum.sort_by(& &1.start, NaiveDateTime)
    |> Enum.reduce([], fn lesson, groups ->
      case groups do
        [group | rest] ->
          if minutes(lesson.start) < Enum.max(Enum.map(group, &minutes(&1.end))),
            do: [group ++ [lesson] | rest],
            else: [[lesson] | groups]

        [] ->
          [[lesson]]
      end
    end)
    |> Enum.reverse()
  end

  defp merge_simultaneous([lesson]), do: lesson

  defp merge_simultaneous(lessons) do
    # Keep genuine simultaneous subjects in one cycle's cell instead of hiding them.
    subjects = lessons |> Enum.map(& &1.subject) |> Enum.uniq()

    lessons
    |> hd()
    |> Map.put(:subject, Enum.map_join(subjects, " / ", &(&1 || "Cours")))
    |> Map.put(:display_subject, Enum.map_join(subjects, " / ", &short_subject/1))
    |> Map.put(:teachers, lessons |> Enum.flat_map(& &1.teachers) |> Enum.uniq())
    |> Map.put(:classrooms, lessons |> Enum.flat_map(& &1.classrooms) |> Enum.uniq())
    |> Map.put(:end, lessons |> Enum.map(& &1.end) |> Enum.max(NaiveDateTime))
  end

  defp minutes(datetime), do: datetime.hour * 60 + datetime.minute

  defp day_name(date),
    do: Enum.at(~w(Lundi Mardi Mercredi Jeudi Vendredi), Date.day_of_week(date) - 1)
end
