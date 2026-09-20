defmodule Pronotex.Pronote.Client do
  @moduledoc false
  alias Pronotex.Pronote.{Crypto, Error, Homework, Lesson, Transport}

  @derive {Inspect, only: []}
  defstruct [:transport, :general, :children, :tabs, homework_reads: %{}, discussion_reads: %{}]

  def login(config, req_options) do
    {parameters, transport} = Transport.open(config, req_options)

    {identification, transport} =
      Transport.call(transport, "Identification", %{
        "data" => %{
          "genreConnexion" => 0,
          "genreEspace" => transport.space,
          "identifiant" => config.username,
          "pourENT" => false,
          "enConnexionAuto" => false,
          "demandeConnexionAuto" => false,
          "demandeConnexionAppliMobile" => false,
          "demandeConnexionAppliMobileJeton" => false,
          "enConnexionAppliMobile" => false,
          "uuidAppliMobile" => "",
          "loginTokenSAV" => ""
        }
      })

    auth_key = Crypto.authentication_key(config.username, config.password, identification)

    challenge =
      Crypto.encrypt(Map.fetch!(identification, "challenge"), auth_key, transport.iv)
      |> Crypto.hex()

    {auth, transport} =
      Transport.call(transport, "Authentification", %{
        "data" => %{
          "connexion" => 0,
          "challenge" => challenge,
          "espace" => transport.space
        }
      })

    unless is_binary(auth["cle"]), do: raise(Error.new(:authentication_failed))
    key_bytes = auth["cle"] |> Crypto.unhex() |> Crypto.decrypt(auth_key, transport.iv)

    key_bytes =
      key_bytes |> String.split(",") |> Enum.map(&String.to_integer/1) |> :erlang.list_to_binary()

    transport = %{transport | key: Crypto.md5(key_bytes)}

    # Registering a device alters account settings. This read-only client never does it.
    actions = get_in(auth, ["actionsDoubleAuth", "V"])

    if actions && Jason.decode!(actions) != [],
      do: raise(Error.new(:additional_authentication_required))

    {user, transport} = Transport.call(transport, "ParametresUtilisateur", %{})

    children =
      if config.space == 3, do: [user["ressource"]], else: user["ressource"]["listeRessources"]

    unless is_list(children) and children != [], do: raise(Error.new(:child_not_found))

    %__MODULE__{
      transport: transport,
      general: Map.fetch!(parameters, "General"),
      children: children,
      tabs: Map.fetch!(user, "listeOnglets")
    }
  end

  def children(client) do
    Enum.map(
      client.children,
      &%{
        id: Map.fetch!(&1, "N"),
        name: Map.fetch!(&1, "L"),
        first_name: &1["prenom"],
        school_name: get_in(&1, ["Etablissement", "V", "L"])
      }
    )
  end

  def lessons(client, child_id, from, to) do
    child = Enum.find(client.children, &(&1["N"] == child_id))
    unless child, do: raise(Error.new(:child_not_found))
    unless contains?(client.tabs, 16), do: raise(Error.new(:forbidden))
    first_monday = Lesson.date(client.general["PremierLundi"]["V"])
    last_day = Lesson.date(client.general["DerniereDate"]["V"])

    if Date.compare(from, first_monday) == :lt or Date.compare(to, last_day) == :gt,
      do: raise(Error.new(:outside_school_year))

    first_week = 1 + div(Date.diff(from, first_monday), 7)
    last_week = 1 + div(Date.diff(to, first_monday), 7)

    {weeks, client} =
      Enum.map_reduce(first_week..last_week, client, fn week, client ->
        data = %{
          "ressource" => child,
          "Ressource" => child,
          "avecAbsencesEleve" => false,
          "avecConseilDeClasse" => true,
          "estEDTPermanence" => false,
          "avecAbsencesRessource" => true,
          "avecDisponibilites" => true,
          "avecInfosPrefsGrille" => true,
          "NumeroSemaine" => week,
          "numeroSemaine" => week
        }

        {result, transport} =
          Transport.call(client.transport, "PageEmploiDuTemps", %{
            "Signature" => signature(client, child_id, 16),
            "data" => data
          })

        lessons =
          Enum.map(Map.fetch!(result, "ListeCours"), &Lesson.parse(&1, client.general, child_id))

        {lessons, %{client | transport: transport}}
      end)

    lessons =
      weeks
      |> List.flatten()
      |> Enum.filter(fn lesson ->
        date = NaiveDateTime.to_date(lesson.start)
        Date.compare(date, from) != :lt and Date.compare(date, to) != :gt
      end)
      |> Enum.uniq_by(&{&1.id, &1.start, &1.priority})
      |> Enum.sort_by(& &1.start, NaiveDateTime)

    {lessons, client}
  end

  def homework(client, child_id, from, to) do
    unless Enum.any?(client.children, &(&1["N"] == child_id)),
      do: raise(Error.new(:child_not_found))

    unless contains?(client.tabs, 88), do: raise(Error.new(:forbidden))
    first_monday = Lesson.date(client.general["PremierLundi"]["V"])
    last_day = Lesson.date(client.general["DerniereDate"]["V"])

    if Date.compare(from, first_monday) == :lt or Date.compare(to, last_day) == :gt,
      do: raise(Error.new(:outside_school_year))

    first_week = 1 + div(Date.diff(from, first_monday), 7)
    last_week = 1 + div(Date.diff(to, first_monday), 7)

    {result, transport} =
      Transport.call(client.transport, "PageCahierDeTexte", %{
        "Signature" => signature(client, child_id, 88),
        "data" => %{"domaine" => %{"_T" => 8, "V" => "[#{first_week}..#{last_week}]"}}
      })

    homework =
      result
      |> Map.fetch!("ListeTravauxAFaire")
      |> Map.fetch!("V")
      |> Enum.map(&Homework.parse(&1, child_id))
      |> Enum.filter(&(Date.compare(&1.date, from) != :lt and Date.compare(&1.date, to) != :gt))
      |> Enum.uniq_by(&{&1.id, &1.date})
      |> Enum.sort_by(& &1.date, Date)

    reads =
      Enum.reduce(homework, client.homework_reads, fn task, acc ->
        Map.put(acc, {child_id, task.id}, {from, to})
      end)

    {homework, %{client | transport: transport, homework_reads: reads}}
  end

  defp signature(%{transport: %{space: 3}}, _child_id, tab), do: %{"onglet" => tab}

  defp signature(_client, child_id, tab),
    do: %{"onglet" => tab, "membre" => %{"N" => child_id, "G" => 4}}

  def set_homework_done(client, child_id, homework_id, done) do
    unless client.transport.space == 3, do: raise(Error.new(:student_credentials_required))

    unless Enum.any?(client.children, &(&1["N"] == child_id)),
      do: raise(Error.new(:child_not_found))

    unless contains?(client.tabs, 88), do: raise(Error.new(:forbidden))

    {from, to} =
      case Map.fetch(client.homework_reads, {child_id, homework_id}) do
        {:ok, range} -> range
        :error -> raise Error.new(:stale_homework)
      end

    {_, transport} =
      Transport.call(client.transport, "SaisieTAFFaitEleve", %{
        "Signature" => signature(client, child_id, 88),
        "data" => %{"listeTAF" => [%{"N" => homework_id, "TAFFait" => done}]}
      })

    {tasks, client} = homework(%{client | transport: transport}, child_id, from, to)

    unless Enum.any?(tasks, &(&1.id == homework_id and &1.done == done)),
      do: raise(Error.new(:homework_unconfirmed))

    {tasks, client}
  end

  # Parent requests require a child context in their signature, even for the
  # parent's own mailbox. The authenticated PRONOTE account owns the messages.
  defp discussion_signature(client), do: signature(client, hd(client.children)["N"], 131)

  def discussions(client) do
    unless client.transport.space in [2, 3], do: raise(Error.new(:forbidden))

    {data, transport} =
      Transport.call(client.transport, "ListeMessagerie", %{
        "Signature" => discussion_signature(client),
        "data" => %{"avecMessage" => true, "avecLu" => true}
      })

    labels = Map.new(get_in(data, ["listeEtiquettes", "V"]) || [], &{&1["N"], &1["G"]})

    rows =
      Enum.filter(get_in(data, ["listeMessagerie", "V"]) || [], fn row ->
        row["estUneDiscussion"] == true and Map.get(row, "profondeur", 1) == 0 and
          not Enum.any?(get_in(row, ["listeEtiquettes", "V"]) || [], &(labels[&1["N"]] in [4, 5]))
      end)

    {discussions, transport} =
      Enum.map_reduce(rows, transport, fn raw, transport ->
        {detail, transport} =
          Transport.call(transport, "ListeMessages", %{
            "Signature" => discussion_signature(client),
            "data" => %{
              "listePossessionsMessages" => get_in(raw, ["listePossessionsMessages", "V"]) || []
            }
          })

        messages = Pronotex.Pronote.Discussion.messages(detail)
        {Pronotex.Pronote.Discussion.parse(raw, messages), transport}
      end)

    reads =
      Map.new(
        rows,
        &{Pronotex.Pronote.Discussion.id(&1), get_in(&1, ["listePossessionsMessages", "V"]) || []}
      )

    {discussions, %{client | transport: transport, discussion_reads: reads}}
  end

  def set_discussion_read(client, id, read) when is_boolean(read) do
    unless client.transport.space in [2, 3], do: raise(Error.new(:forbidden))
    possessions = Map.get(client.discussion_reads, id)
    unless is_list(possessions) and possessions != [], do: raise(Error.new(:stale_discussion))

    {_, transport} =
      Transport.call(client.transport, "SaisieMessage", %{
        "Signature" => discussion_signature(client),
        "data" => %{
          "commande" => "pourLu",
          "lu" => read,
          "listePossessionsMessages" => possessions
        }
      })

    {discussions, client} = discussions(%{client | transport: transport})

    unless Enum.any?(discussions, &(&1.id == id && &1.unread == 0 == read)),
      do: raise(Error.new(:message_unconfirmed))

    {discussions, client}
  end

  def grades(client, child_id, period_name) do
    child = Enum.find(client.children, &(&1["N"] == child_id))
    unless child, do: raise(Error.new(:child_not_found))
    unless contains?(client.tabs, 198), do: raise(Error.new(:forbidden))
    tab = Enum.find(get_in(child, ["listeOngletsPourPeriodes", "V"]) || [], &(&1["G"] == 198))
    unless tab, do: raise(Error.new(:forbidden))
    periods = get_in(tab, ["listePeriodes", "V"]) || []
    default = get_in(tab, ["periodeParDefaut", "V", "N"])

    period =
      Enum.find(
        periods,
        &(&1["L"] == period_name or Pronotex.Pronote.Grades.period_key(&1["L"]) == period_name)
      ) ||
        Enum.find(periods, &(&1["N"] == default)) || List.first(periods)

    unless period, do: raise(Error.new(:forbidden))

    {data, transport} =
      Transport.call(client.transport, "DernieresNotes", %{
        "Signature" => signature(client, child_id, 198),
        "data" => %{"Periode" => Map.take(period, ["N", "L"])}
      })

    report =
      Pronotex.Pronote.Grades.parse(data)
      |> Map.merge(%{period: period["L"], periods: Enum.map(periods, & &1["L"])})

    {report, %{client | transport: transport}}
  end

  def events(client, child_id) do
    child = Enum.find(client.children, &(&1["N"] == child_id))
    unless child, do: raise(Error.new(:child_not_found))
    unless contains?(client.tabs, 9), do: raise(Error.new(:forbidden))

    {data, transport} =
      Transport.call(client.transport, "PageAgenda", %{
        "Signature" => signature(client, child_id, 9),
        "data" => %{
          "AvecListeClasses" => true,
          "avecEventsPasses" => false,
          "avecRdvPartages" => true,
          "listeFamillesFiltre" => nil,
          "uniquementMesEvenements" => false
        }
      })

    events =
      data
      |> Map.fetch!("ListeEvenements")
      |> Enum.filter(&Pronotex.Pronote.Event.for_child?(&1, child))
      |> Enum.map(&Pronotex.Pronote.Event.parse/1)
      |> Enum.uniq_by(&{&1.id, &1.start, &1.end})
      |> Enum.sort_by(& &1.start, NaiveDateTime)

    {events, %{client | transport: transport}}
  end

  def menus(client, child_id, from, to) do
    unless Enum.any?(client.children, &(&1["N"] == child_id)),
      do: raise(Error.new(:child_not_found))

    unless contains?(client.tabs, 10), do: raise(Error.new(:forbidden))
    monday = Date.add(from, 1 - Date.day_of_week(from))

    {weeks, client} =
      Enum.map_reduce(0..div(Date.diff(to, monday), 7), client, fn offset, client ->
        date = Calendar.strftime(Date.add(monday, offset * 7), "%d/%m/%Y") <> " 0:0:0"

        {result, transport} =
          Transport.call(client.transport, "PageMenus", %{
            "Signature" => signature(client, child_id, 10),
            "data" => %{"date" => %{"_T" => 7, "V" => date}}
          })

        menus =
          for day <- Map.fetch!(result, "ListeJours") |> Map.fetch!("V"),
              meal <- get_in(day, ["ListeRepas", "V"]) || [] do
            Pronotex.Pronote.Menu.parse(meal, day["Date"]["V"])
          end

        {menus, %{client | transport: transport}}
      end)

    menus =
      weeks
      |> List.flatten()
      |> Enum.filter(&(Date.compare(&1.date, from) != :lt and Date.compare(&1.date, to) != :gt))
      |> Enum.uniq_by(&{&1.date, &1.id, &1.kind})
      |> Enum.sort_by(& &1.date, Date)

    {menus, client}
  end

  defp contains?(value, target) when is_map(value), do: value |> Map.values() |> contains?(target)
  defp contains?(value, target) when is_list(value), do: Enum.any?(value, &contains?(&1, target))
  defp contains?(value, target), do: value == target
end
