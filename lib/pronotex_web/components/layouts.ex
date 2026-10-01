defmodule PronotexWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PronotexWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :child_theme, :string, default: "blue"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div id="startup-splash" phx-hook="StartupSplash" role="status" aria-label="Connexion en cours">
      <.brand_logo />
    </div>
    <noscript>
      <style>
        #startup-splash { display: none; }
      </style>
    </noscript>
    <div class="page-shell min-h-screen" data-child-theme={@child_theme}>
      <main class="mx-auto max-w-6xl px-4 pt-8 pb-4 sm:px-8 sm:pt-12 sm:pb-6">
        {render_slot(@inner_block)}
      </main>
      <footer class="app-brand-footer">
        <button
          type="button"
          class="app-brand-button"
          data-logo-easter-egg
          aria-label="Animer Captain Notes"
        >
          <.brand_lockup id="footer-logo" class="app-brand-logo" monochrome muted centered />
        </button>
      </footer>
    </div>

    <.flash_group flash={@flash} retry="refresh" />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  attr :retry, :string, default: nil

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash :if={error = Phoenix.Flash.get(@flash, :error)} kind={:error} id="flash-error">
        <span class="whitespace-pre-line">{error}</span>
        <button
          :if={@retry}
          id="retry-error"
          type="button"
          phx-click={@retry}
          class="error-retry"
        >
          Réessayer
        </button>
      </.flash>

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("Connexion Internet perdue")}
        phx-disconnected={
          JS.dispatch("connection-alert:pending", to: ".phx-client-error #client-error")
        }
        phx-connected={JS.dispatch("connection-alert:clear", to: "#client-error")}
        hidden
      >
        {gettext("Tentative de reconnexion en cours…")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Connexion au serveur interrompue")}
        phx-disconnected={
          JS.dispatch("connection-alert:pending", to: ".phx-server-error #server-error")
        }
        phx-connected={JS.dispatch("connection-alert:clear", to: "#server-error")}
        hidden
      >
        {gettext("Tentative de reconnexion en cours…")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
