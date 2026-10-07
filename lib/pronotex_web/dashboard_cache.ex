defmodule PronotexWeb.DashboardCache do
  @moduledoc false
  alias Pronotex.Pronote.{ReadCache, Session, WeekCycle}

  def fetch(%{api: Pronotex.Pronote, account: account} = assigns, name) do
    entries = account.id |> Session.for_account() |> ReadCache.display()
    fetch(entries, assigns, name)
  end

  def fetch(_assigns, _name), do: :miss

  def fetch(entries, assigns, :load) do
    notes =
      Enum.find_value(entries, fn
        {{:grades, {_id, _period}}, snapshot} ->
          if slug(snapshot.child) == assigns.selected_slug and
               (snapshot.period == assigns.grade_period or
                  (is_nil(assigns.grade_period) and snapshot.default?)),
             do: snapshot

        _ ->
          nil
      end)

    children = Map.get(entries, {:children}, if(notes, do: notes.children, else: []))
    child = Enum.find(children, &(slug(&1) == assigns.selected_slug))

    if child do
      today = assigns.today
      from = assigns.week
      agenda_from = assigns.agenda_from

      agenda_to =
        if assigns.mode == :today,
          do: Date.add(Date.beginning_of_week(agenda_from), 4),
          else: Date.add(from, 6)

      operations = %{
        events: {:events, child.id},
        lessons: {:lessons, child.id, agenda_from, agenda_to},
        homework: {:homework, child.id, from, Date.add(from, 6)},
        menus: {:menus, child.id, from, Date.add(from, 6)}
      }

      kinds =
        case assigns.section do
          "agenda" -> [:events, :lessons]
          "devoirs" -> [:homework]
          "cantine" -> [:menus]
          _ -> []
        end

      cached = Map.new(kinds, &{&1, read(entries, operations[&1])})
      available? = Enum.any?(cached, fn {_, result} -> match?({:ok, _}, result) end)

      if available? or (not is_nil(notes) and assigns.section == "notes") or
           assigns.section in ["settings", "timetable", "messages", "parent-messages", "carnet"] do
        urgent =
          case read(
                 entries,
                 {:homework, child.id, today, Pronotex.Pronote.Homework.urgent_until(today)}
               ) do
            {:ok, tasks} -> tasks
            :miss -> nil
          end

        result = %{
          children: children,
          child: child,
          urgent_homework: urgent,
          header_counts: header_counts(entries, child, assigns.account, today),
          events: {:ok, []},
          lessons: {:ok, []},
          homework: {:ok, []},
          menus: {:ok, []},
          grades: if(assigns.section == "notes" and notes, do: {:ok, notes.report}, else: :skip)
        }

        {:ok,
         Enum.reduce(cached, result, fn
           {kind, {:ok, _} = value}, result -> Map.put(result, kind, value)
           _, result -> result
         end)}
      else
        :miss
      end
    else
      :miss
    end
  end

  def fetch(entries, assigns, {:messages_load, _}) do
    operation =
      case assigns.section do
        "carnet" -> {:correspondence, assigns.child.id}
        "parent-messages" -> {:parent_discussions}
        _ -> {:discussions, assigns.child.id}
      end

    result = read(entries, operation)

    case result do
      {:ok, items} when assigns.section == "carnet" ->
        if Pronotex.Pronote.Correspondence.current?(items), do: result, else: :miss

      _ ->
        result
    end
  end

  def fetch(entries, assigns, :week_overview) do
    monday = assigns.week_overview_start
    child = assigns.child

    with {:ok, lessons} <- read(entries, {:lessons, child.id, monday, Date.add(monday, 4)}) do
      case WeekCycle.counterpart(Map.get(child, :week_cycles, %{}), monday) do
        {other_monday, cycle} ->
          case read(entries, {:lessons, child.id, other_monday, Date.add(other_monday, 4)}) do
            {:ok, other} ->
              {:ok, lessons_with_cycle(lessons, other, monday, other_monday, cycle), nil}

            :miss ->
              {:ok, lessons, "Les cours de l’autre cycle sont en cours d’actualisation."}
          end

        nil ->
          {:ok, lessons, nil}
      end
    end
  end

  def fetch(_entries, _assigns, _name), do: :miss

  defp lessons_with_cycle(lessons, other, monday, other_monday, cycle),
    do: WeekCycle.overlay(lessons, other, monday, other_monday, cycle)

  def header_counts(entries, child, account, today) do
    until = Pronotex.Pronote.Homework.urgent_until(today)

    counts =
      case read(entries, {:homework, child.id, today, until}) do
        {:ok, tasks} -> [homework_badge_count: homework_count(tasks, today)]
        :miss -> []
      end

    counts =
      case read(entries, {:discussions, child.id}) do
        {:ok, rows} ->
          Keyword.put(counts, :messages_unread, Enum.sum(Enum.map(rows, & &1.unread)))

        :miss ->
          counts
      end

    if account.role == :parent do
      case read(entries, {:parent_discussions}) do
        {:ok, rows} ->
          Keyword.put(counts, :parent_messages_unread, Enum.sum(Enum.map(rows, & &1.unread)))

        :miss ->
          counts
      end
    else
      counts
    end
  end

  def homework_count(tasks, today) do
    until = Pronotex.Pronote.Homework.urgent_until(today)

    Enum.count(
      tasks,
      &(!&1.done and Date.compare(&1.date, today) != :lt and Date.compare(&1.date, until) != :gt)
    )
  end

  def read(entries, {kind, child, from, to} = operation)
      when kind in [:lessons, :homework, :menus] do
    case Map.fetch(entries, operation) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        entries
        |> Enum.filter(fn
          {{^kind, ^child, cached_from, cached_to}, _} ->
            Date.compare(cached_from, from) != :gt and Date.compare(cached_to, to) != :lt

          _ ->
            false
        end)
        |> Enum.sort_by(fn {{_, _, first, last}, _} -> Date.diff(last, first) end)
        |> case do
          [{_, values} | _] ->
            {:ok,
             Enum.filter(values, fn value ->
               date =
                 if kind == :lessons, do: NaiveDateTime.to_date(value.start), else: value.date

               Date.compare(date, from) != :lt and Date.compare(date, to) != :gt
             end)}

          [] ->
            :miss
        end
    end
  end

  def read(entries, operation) do
    case Map.fetch(entries, operation) do
      {:ok, value} -> {:ok, value}
      :error -> :miss
    end
  end

  defp slug(child),
    do:
      child
      |> Pronotex.Family.first_name()
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/\s+/u, "-")
end
