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

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :child_theme, :string, default: "blue"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div id="startup-splash" phx-hook="StartupSplash" role="status" aria-label="Connexion en cours">
      <svg viewBox="40 45 320 320" aria-hidden="true" focusable="false">
        <defs>
          <mask
            id="startup-skull-mask"
            style="mask-type: alpha"
            maskUnits="userSpaceOnUse"
            x="40"
            y="45"
            width="320"
            height="320"
          >
            <image href={~p"/images/brand/captain-notes-skull-login.png"} width="1040" height="400" />
          </mask>
        </defs>
        <rect
          x="40"
          y="45"
          width="320"
          height="320"
          fill="currentColor"
          mask="url(#startup-skull-mask)"
        />
      </svg>
    </div>
    <noscript>
      <style>
        #startup-splash { display: none; }
      </style>
    </noscript>
    <div class="page-shell min-h-screen" data-child-theme={@child_theme}>
      <main class="mx-auto max-w-6xl px-4 py-8 sm:px-8 sm:py-12">
        {render_slot(@inner_block)}
      </main>
      <footer class="app-brand-footer">
        <button
          type="button"
          class="app-brand-button"
          data-logo-easter-egg
          aria-label="Animer Captain Notes"
        >
          <svg class="app-brand-logo" viewBox="0 0 1040 400" role="img" aria-label="Captain Notes">
            <defs>
              <mask
                id="footer-logo-mask"
                style="mask-type: alpha"
                maskUnits="userSpaceOnUse"
                x="0"
                y="0"
                width="1040"
                height="400"
              >
                <image
                  href={~p"/images/brand/captain-notes-skull-login.png"}
                  width="1040"
                  height="400"
                />
              </mask>
            </defs>
            <g class="app-brand-skull">
              <rect width="365" height="400" fill="currentColor" mask="url(#footer-logo-mask)" />
            </g>
            <rect x="365" width="675" height="400" fill="currentColor" mask="url(#footer-logo-mask)" />
          </svg>
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

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
