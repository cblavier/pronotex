defmodule PronotexWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: PronotexWeb.Gettext

  attr :lesson, :any, required: true

  def lesson_badges(assigns) do
    ~H"""
    <span
      :if={@lesson.canceled}
      class="badge badge-soft badge-error badge-xs"
    >
      Annulé
    </span>
    <.label_badge :if={@lesson.evaluation && !@lesson.canceled}>
      {@lesson.evaluation}
    </.label_badge>
    <span
      :if={@lesson.status && @lesson.status != "" && !@lesson.canceled}
      class="badge badge-soft badge-info badge-xs"
    >
      {if @lesson.status == "Cours modifié",
        do: "Modifié",
        else: @lesson.status}
    </span>
    """
  end

  slot :inner_block, required: true

  def label_badge(assigns) do
    ~H"""
    <span class="badge badge-soft badge-xs warm-badge">{render_slot(@inner_block)}</span>
    """
  end

  attr :label, :string, required: true
  attr :patch, :string, default: nil
  attr :event, :string, default: nil

  def back_link(assigns) do
    ~H"""
    <.link patch={@patch} phx-click={@event} class="lesson-back-link">
      <svg
        width="18"
        height="18"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        aria-hidden="true"
      >
        <path stroke-linecap="round" stroke-linejoin="round" d="m15 18-6-6 6-6" />
      </svg>
      {@label}
    </.link>
    """
  end

  attr :id, :string, required: true
  attr :text, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true

  attr :placement, :string, default: "left", values: ~w(left right)

  def tooltip(assigns) do
    ~H"""
    <span class={["app-tooltip", @class]} data-placement={@placement}>
      {render_slot(@inner_block)}
      <span id={@id} role="tooltip" class="app-tooltip-content">{@text}</span>
    </span>
    """
  end

  attr :id, :string, required: true
  attr :label_id, :string, default: "week-label"
  attr :class, :any, default: nil
  attr :week, :any, required: true
  attr :mode, :atom, default: :week
  attr :cycle, :string, default: nil
  attr :show_cycle, :boolean, default: false
  attr :prefix, :string, default: ""
  attr :week_event, :string, default: "week"
  attr :today_event, :string, default: "today"
  attr :loading, :boolean, required: true
  attr :today_active, :boolean, required: true

  def week_selector(assigns) do
    ~H"""
    <nav id={@id} aria-label="Choisir la semaine" class={["week-selector", @class]}>
      <p id={@label_id} class="week-navigation-label">
        <span class="lg:hidden">
          {if @mode == :today, do: "aujourd’hui", else: compact_week(@week)}
        </span>
        <span class="hidden lg:inline">
          <%= if @mode == :today do %>
            à partir d’aujourd’hui
          <% else %>
            du {Calendar.strftime(@week, "%d/%m")} au {Calendar.strftime(
              Date.add(@week, 6),
              "%d/%m/%Y"
            )}
          <% end %>
        </span>
        <span :if={@show_cycle && @cycle} class="week-cycle-label">({@cycle})</span>
      </p>
      <.week_controls
        prefix={@prefix}
        week_event={@week_event}
        today_event={@today_event}
        loading={@loading}
        today_active={@today_active}
      />
    </nav>
    """
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

  attr :prefix, :string, default: ""
  attr :week_event, :string, default: "week"
  attr :today_event, :string, default: "today"
  attr :loading, :boolean, required: true
  attr :today_active, :boolean, required: true

  def week_controls(assigns) do
    ~H"""
    <div class="flex shrink-0 items-center gap-1">
      <div class="join">
        <button
          id={@prefix <> "previous-week"}
          phx-click={@week_event}
          phx-value-direction="previous"
          disabled={@loading}
          class="btn btn-sm btn-ghost join-item"
          aria-label="Semaine précédente"
        >
          <.icon name="hero-chevron-left" class="size-4" />
        </button>
        <button
          id={@prefix <> "next-week"}
          phx-click={@week_event}
          phx-value-direction="next"
          disabled={@loading}
          class="btn btn-sm btn-ghost join-item"
          aria-label="Semaine suivante"
        >
          <.icon name="hero-chevron-right" class="size-4" />
        </button>
      </div>
      <.tooltip id={@prefix <> "today-tooltip"} text="Aller à aujourd'hui">
        <button
          id={@prefix <> "today-view"}
          phx-click={@today_event}
          disabled={@loading}
          aria-label="Aujourd’hui"
          aria-describedby={@prefix <> "today-tooltip"}
          aria-pressed={to_string(@today_active)}
          class={["btn btn-sm", if(@today_active, do: "btn-soft", else: "btn-ghost")]}
        >
          <.icon name="hero-calendar-days" class="size-4" />
        </button>
      </.tooltip>
    </div>
    """
  end

  @doc "Shared title for application sections such as Messages and Settings."
  attr :id, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def page_title(assigns) do
    ~H"""
    <h2 id={@id} class={["page-title", @class]}>{render_slot(@inner_block)}</h2>
    """
  end

  @doc "Rounded switch using the active child's theme color."
  attr :id, :string, required: true
  attr :checked, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :rest, :global, include: ~w(name value)

  def toggle_switch(assigns) do
    ~H"""
    <input
      id={@id}
      type="checkbox"
      class="toggle app-toggle"
      checked={@checked}
      disabled={@disabled}
      {@rest}
    />
    """
  end

  alias Phoenix.LiveView.JS

  @doc "Shared read status and acknowledgement button for communications."
  attr :discussion, :map, required: true
  attr :saving, :string, default: nil
  attr :loading, :boolean, default: false

  def communication_status_button(assigns) do
    information = Map.get(assigns.discussion, :kind) == :information

    confirmed =
      if information,
        do: Map.get(assigns.discussion, :acknowledged, false),
        else: assigns.discussion.unread == 0

    assigns =
      assign(assigns,
        information: information,
        confirmed: confirmed,
        available: !information || Map.get(assigns.discussion, :acknowledgement_required, false)
      )

    ~H"""
    <button
      :if={@available}
      type="button"
      class="btn btn-sm btn-ghost gap-2 shrink-0 discussion-status"
      aria-pressed={to_string(@confirmed)}
      aria-label={
        if @information,
          do: "J’ai pris connaissance de cette information",
          else: if(@confirmed, do: "Marquer comme non lu", else: "Marquer comme lu")
      }
      data-unread={to_string(!@confirmed)}
      phx-click="mark-discussion"
      phx-value-id={@discussion.id}
      disabled={
        @saving != nil || @loading || (@information && !Map.get(@discussion, :can_acknowledge, false))
      }
    >
      <.icon
        name={if @confirmed, do: "hero-check-circle", else: "hero-minus-circle"}
        class="size-5"
      />
      <%= if @saving == @discussion.id do %>
        <span class="loading loading-spinner loading-xs" role="status">
          <span class="sr-only">Enregistrement en cours</span>
        </span>
      <% else %>
        {if @confirmed, do: "Lu", else: "Non lu"}
      <% end %>
    </button>
    """
  end

  attr :id, :string, required: true
  attr :kind, :atom, default: :discussion
  attr :category, :string, default: nil

  def communication_badge(assigns) do
    {label, icon} =
      case assigns.kind do
        :correspondence -> correspondence_badge(assigns.category)
        :information -> {"Informations", "hero-information-circle"}
        :survey -> {"Sondage", "hero-clipboard-document-check"}
        _ -> {"Discussion", "hero-chat-bubble-left-right"}
      end

    assigns = assign(assigns, label: label, icon: icon)

    ~H"""
    <.tooltip id={@id <> "-tooltip"} text={@label} placement="right" class="shrink-0">
      <span
        class="communication-badge"
        data-kind={@kind}
        role="img"
        aria-label={@label}
        aria-describedby={@id <> "-tooltip"}
        tabindex="0"
      >
        <.icon name={@icon} class="communication-icon" />
      </span>
    </.tooltip>
    """
  end

  defp correspondence_badge(category) do
    icon =
      case category do
        "Absence aux cours" -> "hero-user-minus"
        "Retard" -> "hero-clock"
        "Passage à l’infirmerie" -> "hero-heart"
        "Absence au repas" -> "hero-cake"
        "Dispense" -> "hero-document-check"
        "Punition" -> "hero-no-symbol"
        "Sanction" -> "hero-scale"
        "Absence à l’internat" -> "hero-home"
        "Mesure conservatoire" -> "hero-shield-exclamation"
        "Incident" -> "hero-exclamation-triangle"
        "Commission" -> "hero-user-group"
        "Demande de dispense" -> "hero-document-plus"
        "Retard à l’internat" -> "hero-clock"
        "Défaut de carnet" -> "hero-book-open"
        "Observation" -> "hero-chat-bubble-bottom-center-text"
        "Encouragement" -> "hero-hand-thumb-up"
        _ -> "hero-information-circle"
      end

    {category || "Vie scolaire", icon}
  end

  @doc "A shared count badge for unread messages and homework statuses."
  attr :id, :string, default: nil
  attr :count, :any, required: true
  attr :status, :string, default: "due", values: ~w(done due future)
  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block

  def count_badge(assigns) do
    ~H"""
    <span id={@id} class={["count-badge", @class]} data-status={@status} {@rest}>
      {if @inner_block == [], do: @count, else: render_slot(@inner_block)}
    </span>
    """
  end

  @doc "Displays the shared brand mark."
  attr :variant, :string, default: "detailed", values: ~w(simple detailed)
  attr :class, :string, default: nil

  def brand_logo(assigns) do
    ~H"""
    <span :if={@variant == "simple"} class={["brand-logo-simple", @class]} aria-hidden="true"></span>
    <svg
      :if={@variant == "detailed"}
      class={@class}
      viewBox="0 0 340 330"
      aria-hidden="true"
      focusable="false"
    >
      <image
        class="app-brand-skull"
        href="/images/brand/pronotex-logo-detailed.svg"
        width="340"
        height="330"
      />
    </svg>
    """
  end

  attr :id, :string, required: true
  attr :class, :string, default: nil
  attr :monochrome, :boolean, default: false
  attr :muted, :boolean, default: false
  attr :centered, :boolean, default: false

  def brand_lockup(assigns) do
    ~H"""
    <svg
      class={@class}
      viewBox="0 0 1040 400"
      opacity={if @muted, do: "0.75", else: "1"}
      aria-hidden="true"
      focusable="false"
    >
      <image
        :if={!@monochrome}
        class="app-brand-skull"
        href="/images/brand/pronotex-app-icon.svg"
        x="40"
        y="45"
        width="320"
        height="320"
      />
      <defs :if={@monochrome}>
        <mask
          id={"#{@id}-skull"}
          style="mask-type: alpha"
          maskUnits="userSpaceOnUse"
          x="40"
          y="45"
          width="320"
          height="320"
        >
          <image href="/images/brand/pronotex-logo-simple.svg" x="40" y="45" width="320" height="320" />
        </mask>
      </defs>
      <g :if={@monochrome} class="app-brand-skull">
        <rect x="40" y="45" width="320" height="320" fill="currentColor" mask={"url(##{@id}-skull)"} />
      </g>
      <g transform={if @centered, do: "translate(0 -20)"}>
        <defs>
          <mask
            id={"#{@id}-wordmark"}
            style="mask-type: alpha"
            maskUnits="userSpaceOnUse"
            x="365"
            y="0"
            width="675"
            height="400"
          >
            <image href="/images/brand/captain-notes-wordmark.png" x="365" width="675" height="400" />
          </mask>
        </defs>
        <rect
          x="365"
          width="675"
          height="400"
          fill="currentColor"
          mask={"url(##{@id}-wordmark)"}
        />
      </g>
    </svg>
    """
  end

  @doc "Displays a centered empty-state message with the decorative skull logo."
  attr :id, :string, required: true
  attr :text, :string, required: true

  def empty_state(assigns) do
    ~H"""
    <div id={@id} class="empty-state">
      <p>{@text}</p>
      <.brand_logo variant="simple" class="empty-state-logo" />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :disabled, :boolean, default: false
  attr :rest, :global, include: ~w(aria-controls)

  def show_more_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      class="show-more-button btn btn-sm btn-ghost w-full"
      disabled={@disabled}
      {@rest}
    >
      Voir plus
    </button>
    """
  end

  attr :resources, :list, required: true

  def resource_links(assigns) do
    ~H"""
    <ul :if={@resources != []} class="lesson-resources">
      <li :for={resource <- @resources}>
        <% {prefix, suffix} =
          String.split_at(resource.name, -min(12, div(String.length(resource.name), 2))) %>
        <a
          href={resource.url}
          target="_blank"
          rel="noopener noreferrer"
          class="lesson-resource-link text-sm"
          title={resource.name}
          aria-label={resource.name <> " (nouvel onglet)"}
        >
          <.icon name="hero-paper-clip" />
          <span class="resource-label" aria-hidden="true" phx-no-format><span class="resource-label-prefix">{prefix}</span><span class="resource-label-suffix">{suffix}</span></span>
        </a>
      </li>
    </ul>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and text color classes.

  Icons are embedded from `deps/heroicons` at compile time and rendered as inline SVG.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "utensils"} = assigns) do
    ~H"""
    <svg
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M4 3v5a3 3 0 0 0 6 0V3M7 3v18M18 3c-3 3-4 6-4 10h4M18 3v18" />
    </svg>
    """
  end

  def icon(%{name: "hero-check"} = assigns) do
    ~H"""
    <svg
      class={["icon-check shrink-0", @class]}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2.5"
      aria-hidden="true"
    >
      <path stroke-linecap="round" stroke-linejoin="round" d="m4.5 12.75 6 6 9-13.5" />
    </svg>
    """
  end

  def icon(%{name: "hero-chat-bubble-left-right"} = assigns) do
    ~H"""
    <svg
      class={@class}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      aria-hidden="true"
      data-slot="icon"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M20.25 8.511c.884.284 1.5 1.128 1.5 2.097v4.286c0 1.136-.847 2.1-1.98 2.193-.34.027-.68.052-1.02.072v3.091l-3-3c-1.354 0-2.694-.055-4.02-.163a2.115 2.115 0 0 1-.825-.242m9.345-8.334a2.126 2.126 0 0 0-.476-.095 48.64 48.64 0 0 0-8.048 0c-1.131.094-1.976 1.057-1.976 2.192v4.286c0 .837.46 1.58 1.155 1.951m9.345-8.334V6.637c0-1.621-1.152-3.026-2.76-3.235A48.455 48.455 0 0 0 11.25 3c-2.115 0-4.198.137-6.24.402-1.608.209-2.76 1.614-2.76 3.235v6.226c0 1.621 1.152 3.026 2.76 3.235.577.075 1.157.14 1.74.194V21l4.155-4.155"
      />
    </svg>
    """
  end

  def icon(%{name: "hero-information-circle"} = assigns) do
    ~H"""
    <svg
      class={@class}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      aria-hidden="true"
      data-slot="icon"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="m11.25 11.25.041-.02a.75.75 0 0 1 1.063.852l-.708 2.836a.75.75 0 0 0 1.063.853l.041-.021M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9-3.75h.008v.008H12V8.25Z"
      />
    </svg>
    """
  end

  def icon(%{name: "hero-clipboard-document-check"} = assigns) do
    ~H"""
    <svg
      class={@class}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      aria-hidden="true"
      data-slot="icon"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M11.35 3.836c-.065.21-.1.433-.1.664 0 .414.336.75.75.75h4.5a.75.75 0 0 0 .75-.75 2.25 2.25 0 0 0-.1-.664m-5.8 0A2.251 2.251 0 0 1 13.5 2.25H15c1.012 0 1.867.668 2.15 1.586m-5.8 0c-.376.023-.75.05-1.124.08C9.095 4.01 8.25 4.973 8.25 6.108V8.25m8.9-4.414c.376.023.75.05 1.124.08 1.131.094 1.976 1.057 1.976 2.192V16.5A2.25 2.25 0 0 1 18 18.75h-2.25m-7.5-10.5H4.875c-.621 0-1.125.504-1.125 1.125v11.25c0 .621.504 1.125 1.125 1.125h9.75c.621 0 1.125-.504 1.125-1.125V18.75m-7.5-10.5h6.375c.621 0 1.125.504 1.125 1.125v9.375m-8.25-3 1.5 1.5 3-3.75"
      />
    </svg>
    """
  end

  def icon(%{name: "hero-paper-clip"} = assigns) do
    ~H"""
    <svg
      width="18"
      height="18"
      class={@class}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      aria-hidden="true"
      data-slot="icon"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="m18.375 12.739-7.693 7.693a4.5 4.5 0 0 1-6.364-6.364l10.94-10.94A3 3 0 1 1 19.5 7.372L8.552 18.32m.009-.01-.01.01m5.699-9.941-7.81 7.81a1.5 1.5 0 0 0 2.112 2.13"
      />
    </svg>
    """
  end

  def icon(%{name: "hero-" <> _} = assigns) do
    {attributes, content} = PronotexWeb.Heroicons.fetch!(assigns.name)
    assigns = assign(assigns, svg_attributes: attributes, svg_content: content)

    ~H"""
    <svg {@svg_attributes} class={[@class, "inline-block align-middle"]} focusable="false">
      {@svg_content}
    </svg>
    """
  end

  @doc "A themed dropdown for both LiveView and ordinary HTML forms."
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :options, :list, required: true
  attr :value, :string, default: nil
  attr :disabled, :boolean, default: false

  def dropdown(assigns) do
    selected =
      Enum.find(assigns.options, fn {_, value} -> value == assigns.value end) ||
        List.first(assigns.options)

    assigns = assign(assigns, :selected, selected)

    ~H"""
    <details id={@id <> "-picker"} class="themed-dropdown" data-dropdown>
      <summary id={@id} aria-label={@label}>
        <span data-dropdown-label>{if @selected, do: elem(@selected, 0)}</span>
        <.icon name="hero-chevron-down" class="size-4 shrink-0" />
      </summary>
      <div class="dropdown-options" role="group" aria-label={@label}>
        <label :for={{label, value} <- @options} class="dropdown-option">
          <input
            type="radio"
            name={@name}
            value={value}
            checked={@selected && value == elem(@selected, 1)}
            disabled={@disabled}
          />
          <span data-option-label>{label}</span>
          <.icon name="hero-check" class="size-4 dropdown-check" />
        </label>
      </div>
    </details>
    """
  end

  ## JS Commands

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end
end
