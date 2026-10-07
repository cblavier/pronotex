defmodule PronotexWeb.MessageComponents do
  use PronotexWeb, :html

  attr :entry, :map, required: true

  def justification_badge(assigns) do
    assigns = assign(assigns, :justified, Map.get(assigns.entry, :justified))

    ~H"""
    <span
      :if={is_boolean(@justified)}
      class="btn btn-sm btn-ghost gap-2 shrink-0 discussion-status justification-badge"
      data-unread={to_string(!@justified)}
    >
      <.icon name={if @justified, do: "hero-check-circle", else: "hero-minus-circle"} class="size-5" />
      {if @justified, do: "Justifiée", else: "Non justifiée"}
    </span>
    """
  end

  attr :entry, :map, required: true
  attr :today, Date, required: true

  def correspondence_summary(assigns) do
    assigns = assign(assigns, :date_label, correspondence_date(assigns.entry, assigns.today))

    ~H"""
    <span class="discussion-heading communication-heading correspondence-summary">
      <.communication_badge
        id={"communication-#{@entry.id}"}
        kind={:correspondence}
        category={Map.get(@entry, :category)}
      />
      <span class="correspondence-summary-text">
        <strong>{Map.get(@entry, :summary_title, @entry.subject)}</strong>
        <span>{@date_label}</span>
      </span>
    </span>
    """
  end

  defp correspondence_date(entry, today) do
    start = Pronotex.Pronote.Lesson.datetime(entry.date)
    ending = Map.get(entry, :end_date)
    ending = if is_binary(ending) and ending != "", do: Pronotex.Pronote.Lesson.datetime(ending)

    cond do
      ending && NaiveDateTime.to_date(start) != NaiveDateTime.to_date(ending) ->
        "Du #{short_date(start, today)} à #{hour(start)} au #{short_date(ending, today)} à #{hour(ending)}"

      ending && start != ending ->
        "#{day_label(start, today)} de #{hour(start)} à #{hour(ending)}"

      true ->
        day_label(start, today)
    end
  rescue
    _ in [Pronotex.Pronote.Error, ArgumentError] -> entry.date
  end

  defp day_label(date, today) do
    if NaiveDateTime.to_date(date) == today,
      do: "Aujourd’hui",
      else: "Le " <> short_date(date, today)
  end

  defp short_date(date, today) do
    month =
      Enum.at(~w(janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.), date.month - 1)

    year = if date.year == today.year, do: "", else: " #{date.year}"
    "#{date.day} #{month}#{year}"
  end

  defp hour(date),
    do: "#{date.hour}h#{String.pad_leading(Integer.to_string(date.minute), 2, "0")}"

  attr :loading, :boolean, required: true
  slot :inner_block, required: true

  def recipient_field(assigns) do
    ~H"""
    <div class="recipient-field" data-loading={to_string(@loading)} aria-busy={to_string(@loading)}>
      {render_slot(@inner_block)}
      <span :if={@loading} class="recipient-field-spinner" role="status">
        <span class="recipient-loading-ring" aria-hidden="true"></span>
        <span class="sr-only">Chargement des destinataires…</span>
      </span>
    </div>
    """
  end

  attr :message, :map, required: true
  attr :details, :boolean, default: false
  attr :id, :string, default: "message-correspondents"

  def message_correspondents(assigns) do
    own = Map.get(assigns.message, :own, false)

    recipients =
      (Map.get(assigns.message, :recipients) || [])
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    sender = %{direction: "received", label: "De :", names: assigns.message.author}
    expandable = assigns.details and length(recipients) > 2

    recipient = %{
      direction: "sent",
      label: "À :",
      names: if(expandable, do: hd(recipients), else: Enum.join(recipients, ", "))
    }

    rows =
      if assigns.details,
        do: [sender, recipient],
        else: [if(own, do: recipient, else: sender)]

    rows = Enum.reject(rows, &(&1.direction == "sent" and &1.names == ""))
    assigns = assign(assigns, rows: rows, recipients: recipients, expandable: expandable)

    ~H"""
    <span :if={@rows != []} class="message-correspondents">
      <strong :for={row <- @rows} class="message-correspondent-line">
        <span class="message-direction" data-direction={row.direction}>{row.label}</span>
        {row.names}
        <.link
          :if={row.direction == "sent" && @expandable}
          id={@id <> "-toggle"}
          href="#"
          class="message-recipients-toggle"
          aria-expanded="false"
          aria-controls={@id <> "-all"}
          aria-label="Afficher ou masquer tous les destinataires"
          phx-click={
            JS.toggle(to: "##{@id}-all")
            |> JS.toggle_attribute({"aria-expanded", "true", "false"}, to: "##{@id}-toggle")
          }
        >
          <span class="message-recipients-count">+{length(@recipients) - 1}</span>
          <.icon name="hero-chevron-down" class="message-recipients-chevron size-4" />
        </.link>
        <span
          :if={row.direction == "sent" && @expandable}
          id={@id <> "-all"}
          class="message-recipients-all"
          style="display: none;"
        >
          {Enum.join(@recipients, ", ")}
        </span>
      </strong>
    </span>
    """
  end

  attr :recipient, :map, required: true

  def recipient_badges(assigns) do
    ~H"""
    <span class="recipient-name">{@recipient.name}</span>
    <.label_badge>{@recipient.type}</.label_badge>
    <span :for={subject <- @recipient.subjects} class="badge badge-xs recipient-subject-badge">
      {subject}
    </span>
    """
  end

  attr :kind, :atom, required: true
  attr :recipients, :list, required: true
  attr :subject, :string, required: true
  attr :return_focus, :string, default: "#message-subject"

  def message_confirmation(assigns) do
    ~H"""
    <div id="message-confirmation" class="message-modal-backdrop">
      <.focus_wrap
        id="message-confirmation-focus"
        phx-mounted={JS.focus_first(to: "#message-confirmation-focus")}
        phx-remove={JS.focus(to: @return_focus)}
      >
        <section
          role="alertdialog"
          aria-modal="true"
          aria-labelledby="confirmation-title"
          aria-describedby="confirmation-description"
          class="message-modal"
          phx-window-keydown="dismiss-confirmation"
          phx-key="Escape"
        >
          <h2 id="confirmation-title" class="page-title">
            {if @kind == :send, do: "Envoyer ce message ?", else: "Abandonner ce message ?"}
          </h2>
          <div id="confirmation-description">
            <%= if @kind == :send do %>
              <p><strong>{@subject}</strong></p>
              <p>À {Enum.map_join(@recipients, ", ", & &1.name)}</p>
            <% else %>
              <p>Votre saisie sera perdue.</p>
            <% end %>
          </div>
          <div class="message-form-actions">
            <button
              id="dismiss-confirmation"
              type="button"
              class="btn btn-sm themed-mini-button"
              phx-click="dismiss-confirmation"
            >
              Continuer la rédaction
            </button>
            <button
              id="confirm-message-action"
              type="button"
              class="btn btn-sm themed-mini-button message-primary-button"
              phx-click={if @kind == :send, do: "confirm-send", else: "confirm-cancel"}
            >
              {if @kind == :send, do: "Confirmer l’envoi", else: "Abandonner"}
            </button>
          </div>
        </section>
      </.focus_wrap>
    </div>
    """
  end
end
