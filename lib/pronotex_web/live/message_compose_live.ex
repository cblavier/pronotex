defmodule PronotexWeb.MessageComposeLive do
  use PronotexWeb, :live_view
  import PronotexWeb.MessageComponents
  alias Pronotex.Pronote.Recipient

  def allowed?(%{role: :parent}, "parent-messages"), do: true
  def allowed?(%{role: :child}, "messages"), do: true
  def allowed?(_, _), do: false

  @impl true
  def mount(%{"child" => slug, "section" => section}, _session, socket) do
    if allowed?(socket.assigns.account, section) do
      socket =
        assign(socket,
          page_title: "Nouveau message",
          slug: slug,
          section: section,
          back_url: ~p"/#{slug}/#{section}",
          api: Application.get_env(:pronotex, :pronote_client, Pronotex.Pronote),
          children: [],
          child: nil,
          today: Application.get_env(:pronotex, :today, &Date.utc_today/0).(),
          messages_unread: 0,
          parent_messages_unread: 0,
          homework_badge_count: 0,
          pending_destination: nil,
          recipients: [],
          selected: [],
          sender_name: socket.assigns.account.label,
          subject: "",
          content: "",
          query: "",
          loading: true,
          load_error: nil,
          form_error: nil,
          dropdown: false,
          confirmation: nil,
          sending: false,
          sent: false,
          uncertain: false
        )

      {:ok, if(connected?(socket), do: load_recipients(socket), else: socket)}
    else
      {:ok,
       socket
       |> put_flash(:error, "La rédaction est réservée à votre propre messagerie.")
       |> redirect(to: "/")}
    end
  end

  defp load_recipients(socket) do
    api = socket.assigns.api
    account = socket.assigns.account
    slug = socket.assigns.slug

    socket
    |> assign(loading: true, load_error: nil)
    |> start_async(:recipients, fn ->
      with {:ok, children} <- call(api, account, :children, []),
           true <- Enum.any?(children, &(child_slug(&1) == slug)) do
        sender_name =
          case call(api, account, :sender_name, []) do
            {:ok, name} when is_binary(name) and name != "" -> name
            _ -> account.label
          end

        {:ok, children, sender_name, call(api, account, :message_recipients, [])}
      else
        false -> {:error, Pronotex.Pronote.Error.new(:child_not_found)}
        error -> error
      end
    end)
  end

  @impl true
  def handle_async(:recipients, {:ok, {:ok, children, sender_name, result}}, socket) do
    child = Enum.find(children, &(child_slug(&1) == socket.assigns.slug))

    socket =
      socket
      |> assign(children: children, child: child, sender_name: sender_name)
      |> load_header_counts()

    case result do
      {:ok, recipients} ->
        {:noreply, assign(socket, loading: false, recipients: recipients, load_error: nil)}

      _ ->
        handle_async(:recipients, :error, socket)
    end
  end

  def handle_async(:header_counts, {:ok, counts}, socket), do: {:noreply, assign(socket, counts)}
  def handle_async(:header_counts, _, socket), do: {:noreply, socket}

  def handle_async(:recipients, _, socket),
    do:
      {:noreply,
       assign(socket,
         loading: false,
         load_error: "Impossible de charger les destinataires depuis Pronote."
       )}

  def handle_async(:send, {:ok, {:ok, result}}, socket) when result in [:sent, :simulated] do
    confirmation =
      if result == :simulated,
        do:
          "Envoi simulé : aucun message n’a été envoyé à Pronote. Le payload est disponible dans les logs.",
        else: "Votre message a été envoyé."

    {:noreply,
     socket
     |> assign(sending: false, sent: true, selected: [], subject: "", content: "")
     |> put_flash(:message_sent, confirmation)
     |> push_navigate(to: socket.assigns.back_url)}
  end

  def handle_async(:send, _, socket) do
    {:noreply,
     assign(socket,
       sending: false,
       uncertain: true,
       form_error:
         "L’envoi n’a pas pu être confirmé. Votre saisie est conservée. Vérifiez votre messagerie Pronote avant de réessayer pour éviter un doublon."
     )}
  end

  @impl true
  def handle_event("refresh", _, socket) do
    {:noreply,
     if(socket.assigns.sending or socket.assigns.sent, do: socket, else: load_recipients(socket))}
  end

  def handle_event(_, _, %{assigns: %{sending: true}} = socket), do: {:noreply, socket}

  def handle_event("section", %{"section" => section}, socket)
      when section in [
             "agenda",
             "devoirs",
             "notes",
             "cantine",
             "settings",
             "messages",
             "parent-messages"
           ] do
    if section != "parent-messages" or socket.assigns.account.role == :parent do
      path =
        case section do
          "agenda" -> ~p"/#{socket.assigns.slug}"
          "cantine" -> ~p"/#{socket.assigns.slug}/menu"
          "settings" -> ~p"/#{socket.assigns.slug}/reglages"
          other -> ~p"/#{socket.assigns.slug}/#{other}"
        end

      request_navigation(socket, path)
    else
      {:noreply, socket}
    end
  end

  def handle_event("select-child", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.children, &(&1.id == id)) do
      nil -> {:noreply, socket}
      child -> request_navigation(socket, ~p"/#{child_slug(child)}/#{socket.assigns.section}")
    end
  end

  def handle_event("request-logout", _, socket), do: request_navigation(socket, :logout)

  def handle_event(_, _, %{assigns: %{sent: true}} = socket), do: {:noreply, socket}

  def handle_event("verified-not-sent", _, socket) do
    {:noreply, socket |> assign(uncertain: false, form_error: nil) |> load_recipients()}
  end

  def handle_event("change", %{"draft" => draft} = params, socket) do
    {:noreply,
     assign(socket,
       subject: Map.get(draft, "subject", socket.assigns.subject),
       content: Map.get(draft, "content", socket.assigns.content),
       query: Map.get(draft, "query", socket.assigns.query),
       dropdown: params["_target"] == ["draft", "query"],
       confirmation: nil,
       form_error: nil
     )}
  end

  def handle_event("show-recipients", _, socket), do: {:noreply, assign(socket, dropdown: true)}
  def handle_event("hide-recipients", _, socket), do: {:noreply, assign(socket, dropdown: false)}

  def handle_event("add-recipient", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.recipients, &(&1.id == id)) do
      {:noreply,
       socket
       |> assign(
         selected: Enum.uniq(socket.assigns.selected ++ [id]),
         query: "",
         dropdown: false,
         confirmation: nil
       )
       |> push_event("recipient-selected", %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove-recipient", %{"id" => id}, socket),
    do:
      {:noreply,
       assign(socket, selected: List.delete(socket.assigns.selected, id), confirmation: nil)}

  def handle_event("review-send", %{"draft" => draft}, socket) do
    socket = assign(socket, subject: draft["subject"] || "", content: draft["content"] || "")

    if valid?(socket.assigns) do
      {:noreply, assign(socket, confirmation: :send, dropdown: false, form_error: nil)}
    else
      {:noreply,
       assign(socket,
         form_error:
           "Choisissez au moins un destinataire et renseignez l’objet et le message (200 et 20 000 caractères maximum)."
       )}
    end
  end

  def handle_event("confirm-send", _, %{assigns: %{confirmation: :send}} = socket) do
    if valid?(socket.assigns) do
      %{api: api, account: account, selected: ids, subject: subject, content: content} =
        socket.assigns

      {:noreply,
       socket
       |> assign(sending: true, confirmation: nil)
       |> start_async(:send, fn ->
         call(api, account, :send_message, [ids, subject, content])
       end)}
    else
      {:noreply, assign(socket, confirmation: nil)}
    end
  end

  def handle_event("cancel", _, socket), do: request_navigation(socket, socket.assigns.back_url)

  def handle_event("confirm-cancel", _, %{assigns: %{confirmation: :cancel}} = socket),
    do: navigate(socket, socket.assigns.pending_destination)

  def handle_event("dismiss-confirmation", _, socket),
    do: {:noreply, assign(socket, confirmation: nil)}

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp request_navigation(socket, destination) do
    if dirty?(socket.assigns),
      do:
        {:noreply,
         assign(socket, confirmation: :cancel, dropdown: false, pending_destination: destination)},
      else: navigate(socket, destination)
  end

  defp navigate(socket, :logout), do: {:noreply, push_event(socket, "compose-logout", %{})}
  defp navigate(socket, destination), do: {:noreply, push_navigate(socket, to: destination)}

  defp load_header_counts(socket) do
    %{api: api, account: account, child: child, today: today} = socket.assigns

    start_async(socket, :header_counts, fn ->
      until = Pronotex.Pronote.Homework.urgent_until(today)

      homework =
        case call(api, account, :homework, [child.id, today, until]) do
          {:ok, tasks} ->
            Enum.count(
              tasks,
              &(!&1.done and Date.compare(&1.date, today) != :lt and
                  Date.compare(&1.date, until) != :gt)
            )

          _ ->
            0
        end

      child_available = account.role == :child or api.homework_writable?(child)

      messages =
        if child_available, do: unread(call(api, account, :discussions, [child.id])), else: 0

      parent =
        if account.role == :parent,
          do: unread(call(api, account, :parent_discussions, [])),
          else: 0

      [homework_badge_count: homework, messages_unread: messages, parent_messages_unread: parent]
    end)
  end

  defp unread({:ok, discussions}), do: Enum.sum(Enum.map(discussions, & &1.unread))
  defp unread(_), do: 0

  defp valid?(assigns) do
    !assigns.loading and !assigns.uncertain and is_nil(assigns.load_error) and
      Recipient.valid_message?(assigns.selected, assigns.subject, assigns.content) and
      Enum.all?(assigns.selected, fn id -> Enum.any?(assigns.recipients, &(&1.id == id)) end)
  end

  defp dirty?(assigns),
    do: assigns.selected != [] or assigns.subject != "" or assigns.content != ""

  defp selected_recipients(assigns),
    do: Enum.filter(assigns.recipients, &(&1.id in assigns.selected))

  defp matching_recipients(assigns) do
    query = normalize(assigns.query)

    assigns.recipients
    |> Enum.reject(&(&1.id in assigns.selected))
    |> Enum.filter(&(normalize(Enum.join([&1.name, &1.type | &1.subjects], " ")) =~ query))
  end

  defp normalize(value),
    do: value |> String.downcase() |> String.normalize(:nfd) |> String.replace(~r/\p{Mn}/u, "")

  defp child_slug(child),
    do:
      child
      |> Pronotex.Family.first_name()
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/\s+/u, "-")

  defp call(Pronotex.Pronote, account, operation, args),
    do:
      apply(
        Pronotex.Pronote,
        operation,
        args ++ [Pronotex.Pronote.Session.for_account(account.id)]
      )

  defp call(api, _, operation, args), do: apply(api, operation, args)
end
