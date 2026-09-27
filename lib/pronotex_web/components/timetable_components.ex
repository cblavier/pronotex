defmodule PronotexWeb.TimetableComponents do
  use Phoenix.Component
  import PronotexWeb.CoreComponents

  attr :lessons, :list, required: true
  attr :monday, :any, required: true
  attr :loading, :boolean, required: true
  attr :error, :any, default: nil
  attr :child_name, :string, required: true

  def week_timetable(assigns) do
    days = for offset <- 0..4, do: Date.add(assigns.monday, offset)
    lessons = Enum.filter(assigns.lessons, &(NaiveDateTime.to_date(&1.start) in days))
    first = min(8 * 60, Enum.min(Enum.map(lessons, &minutes(&1.start)), fn -> 8 * 60 end))
    last = max(17 * 60, Enum.max(Enum.map(lessons, &minutes(&1.end)), fn -> 17 * 60 end))
    first = div(first, 60) * 60
    last = div(last + 59, 60) * 60
    assigns = assign(assigns, days: days, entries: lessons, first: first, last: last)

    ~H"""
    <dialog
      id="week-overview"
      phx-hook="WeekOverview"
      class="week-overview"
      aria-labelledby="week-overview-title"
    >
      <div class="week-overview-surface">
        <header class="week-overview-header">
          <h2 id="week-overview-title">
            {@child_name} · {Calendar.strftime(@monday, "%d/%m")} – {Calendar.strftime(
              Date.add(@monday, 4),
              "%d/%m"
            )}
          </h2>
          <button
            type="button"
            phx-click="close-week-overview"
            aria-label="Fermer l’emploi du temps"
            class="btn btn-sm btn-ghost"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </header>
        <p :if={@loading} role="status" class="week-overview-message">Chargement de la semaine…</p>
        <div :if={@error} role="alert" class="week-overview-message">
          <p>{@error}</p>
          <button type="button" phx-click="open-week-overview" class="btn btn-sm">Réessayer</button>
        </div>
        <div :if={!@loading && !@error} class="week-grid">
          <div class="week-hours" aria-hidden="true">
            <span
              :for={minute <- @first..(@last - 1)//60}
              style={"top: #{100 * (minute - @first) / (@last - @first)}%"}
            >
              {div(minute, 60)}h
            </span>
          </div>
          <section :for={date <- @days} class="week-column" aria-label={day_name(date)}>
            <h3>{day_name(date)} <span>{Calendar.strftime(date, "%d/%m")}</span></h3>
            <div
              class="week-column-body"
              style={"grid-template-rows: repeat(#{@last - @first}, minmax(0, 1fr)); --hour-height: #{6000 / (@last - @first)}%"}
            >
              <article
                :for={{lesson, lane, lanes} <- positioned(@entries, date)}
                class={["week-lesson", lesson.canceled && "week-lesson-canceled"]}
                style={"top: #{100 * (minutes(lesson.start) - @first) / (@last - @first)}%; height: #{100 * (minutes(lesson.end) - minutes(lesson.start)) / (@last - @first)}%; left: #{100 * lane / lanes}%; width: #{100 / lanes}%; --subject-color: #{lesson.color || "#94a3b8"}"}
                aria-label={"#{lesson.subject || "Cours"}, #{Calendar.strftime(lesson.start, "%H:%M")}–#{Calendar.strftime(lesson.end, "%H:%M")}"}
              >
                <span class="week-subject">{lesson.subject || "Cours"}</span>
                <div class="week-badges"><.lesson_badges lesson={lesson} /></div>
              </article>
            </div>
          </section>
          <p :if={@entries == []} class="week-empty">Aucun cours cette semaine.</p>
        </div>
      </div>
    </dialog>
    """
  end

  # Only simultaneous lessons share a column; other lessons use its full width.
  defp positioned(lessons, date) do
    lessons
    |> Enum.filter(&(NaiveDateTime.to_date(&1.start) == date))
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
    |> Enum.flat_map(fn group ->
      {placed, ends} =
        Enum.map_reduce(group, [], fn lesson, ends ->
          lane = Enum.find_index(ends, &(&1 <= minutes(lesson.start))) || length(ends)

          ends =
            if lane == length(ends),
              do: ends ++ [minutes(lesson.end)],
              else: List.replace_at(ends, lane, minutes(lesson.end))

          {{lesson, lane}, ends}
        end)

      Enum.map(placed, fn {lesson, lane} -> {lesson, lane, length(ends)} end)
    end)
  end

  defp minutes(datetime), do: datetime.hour * 60 + datetime.minute

  defp day_name(date),
    do: Enum.at(~w(Lundi Mardi Mercredi Jeudi Vendredi), Date.day_of_week(date) - 1)
end
