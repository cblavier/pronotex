defmodule PronotexWeb.MessageComponents do
  use PronotexWeb, :html

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

  def message_confirmation(assigns) do
    ~H"""
    <div id="message-confirmation" class="message-modal-backdrop">
      <.focus_wrap
        id="message-confirmation-focus"
        phx-mounted={JS.focus_first(to: "#message-confirmation-focus")}
        phx-remove={JS.focus(to: "#message-subject")}
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
