defmodule PronotexWeb.AppHeader do
  use PronotexWeb, :html
  import PronotexWeb.NotificationComponents

  attr :account, :map, required: true
  attr :children, :list, required: true
  attr :child, :any, required: true
  attr :section, :string, required: true
  attr :loading, :boolean, default: false
  attr :current_url, :string, required: true
  attr :today, :any, required: true
  attr :received_notifications, :list, default: []
  attr :messages_unread, :integer, default: 0
  attr :parent_messages_unread, :integer, default: 0
  attr :homework_badge_count, :integer, default: 0
  attr :logout_event, :string, default: nil
  slot :inner_block

  def header(assigns) do
    ~H"""
    <div
      id="responsive-header"
      phx-hook="RememberPage"
      data-page-account={@account.id}
      data-page-url={@current_url}
      data-page-ready={to_string(!@loading)}
    >
      <header id="child-header" class="pb-8">
        <details
          :if={@child}
          id="child-picker"
          phx-click-away={JS.remove_attribute("open", to: "#child-picker")}
          phx-window-keydown={JS.remove_attribute("open", to: "#child-picker")}
          phx-key="Escape"
        >
          <summary id="child-picker-toggle" aria-label="Choisir un enfant ou se déconnecter">
            <span class="child-avatar-wrapper">
              <span class="child-picker-avatar">
                <img :if={avatar_src(@child)} id="child-avatar" src={avatar_src(@child)} alt="" />
                <span :if={!avatar_src(@child)} id="child-initials">
                  {String.first(first_name(@child))}
                </span>
              </span>
              <span
                :if={@messages_unread + @parent_messages_unread > 0}
                id="messages-avatar-dot"
                class="messages-unread-dot"
                aria-label="Messages non lus"
              >
              </span>
            </span>
            <div id="child-identity">
              <p
                :if={@child && Map.get(@child, :school_name) not in [nil, ""]}
                id="school-name"
                class="mb-1 text-xs font-medium text-[var(--muted-ink)] sm:text-sm"
              >
                {Map.get(@child, :school_name)}
                <span :if={Map.get(@child, :class_name) not in [nil, ""]}>
                  / {Map.get(@child, :class_name)}
                </span>
              </p>
              <div class="child-picker-name-row">
                <h1 id="child-name" class="font-semibold tracking-tight">{first_name(@child)}</h1>
                <svg
                  class="child-picker-chevron"
                  width="20"
                  height="20"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  aria-hidden="true"
                >
                  <path d="m6 9 6 6 6-6" stroke-linecap="round" stroke-linejoin="round" />
                </svg>
              </div>
            </div>
          </summary>
          <div id="child-picker-panel">
            <ul aria-label="Enfants">
              <li :for={child <- @children} :if={child.id != @child.id}>
                <button
                  type="button"
                  class="child-picker-option"
                  data-child-id={child.id}
                  phx-click={
                    JS.push("select-child", value: %{id: child.id})
                    |> JS.remove_attribute("open", to: "#child-picker")
                  }
                  disabled={@loading}
                >
                  <span class="child-option-avatar">
                    <img :if={avatar_src(child)} src={avatar_src(child)} alt="" />
                    <span :if={!avatar_src(child)}>{String.first(first_name(child))}</span>
                  </span>
                  <span>{first_name(child)}</span>
                </button>
              </li>
            </ul>
            <hr
              :if={Enum.any?(@children, &(&1.id != @child.id))}
              class="child-picker-separator"
            />
            <button
              :if={@account.role == :parent}
              id="open-parent-messages"
              type="button"
              class="child-picker-option"
              phx-click={
                JS.push("section", value: %{section: "parent-messages"})
                |> JS.remove_attribute("open", to: "#child-picker")
              }
              aria-current={if @section == "parent-messages", do: "page"}
              disabled={@loading}
            >
              <svg
                width="24"
                height="24"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="1.5"
                aria-hidden="true"
              >
                <rect x="3" y="5" width="18" height="14" rx="2" /><path d="m3 6 9 7 9-7" />
              </svg>
              <span>{messages_label(@account, @child, "parent-messages")}</span>
              <.count_badge
                :if={@parent_messages_unread > 0}
                id="parent-messages-unread-count"
                aria-label={"#{@parent_messages_unread} messages non lus"}
                count={@parent_messages_unread}
              />
            </button>
            <button
              id="open-messages"
              type="button"
              class="child-picker-option"
              phx-click={
                JS.push("section", value: %{section: "messages"})
                |> JS.remove_attribute("open", to: "#child-picker")
              }
              aria-current={if @section == "messages", do: "page"}
              disabled={@loading}
            >
              <svg
                width="24"
                height="24"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="1.5"
                aria-hidden="true"
              >
                <rect x="3" y="5" width="18" height="14" rx="2" /><path d="m3 6 9 7 9-7" />
              </svg>
              <span>{messages_label(@account, @child, "messages")}</span>
              <.count_badge
                :if={@messages_unread > 0}
                id="messages-unread-count"
                aria-label={"#{@messages_unread} messages non lus"}
                count={@messages_unread}
              />
            </button>
            <button
              id="open-settings"
              type="button"
              class="child-picker-option"
              phx-click={
                JS.push("section", value: %{section: "settings"})
                |> JS.remove_attribute("open", to: "#child-picker")
              }
              aria-current={if @section == "settings", do: "page"}
              disabled={@loading}
            >
              <.icon name="hero-cog-6-tooth" class="size-6" />
              <span>Réglages</span>
            </button>
            <.form
              :if={Pronotex.Auth.enabled?()}
              for={%{}}
              action={~p"/logout"}
              phx-submit={@logout_event}
              class="child-picker-logout"
            >
              <button
                id="logout"
                type="submit"
                disabled={@logout_event && @loading}
                class="child-picker-option"
              >
                <.icon name="hero-arrow-right-on-rectangle" class="size-6" />
                <span>Se déconnecter</span>
              </button>
            </.form>
          </div>
        </details>
      </header>

      <.notification_banners
        notifications={@received_notifications}
        children={@children}
        scope={Pronotex.Push.inbox_scope(@account.id)}
      />

      <div
        id="dashboard-navigation"
        class="mb-6 flex flex-nowrap items-center justify-between gap-x-3 border-b border-base-300 text-[var(--muted-ink)]"
      >
        <nav
          id="section-navigation"
          aria-label="Rubriques"
          class="flex max-w-full items-center gap-3 overflow-x-auto lg:gap-6"
        >
          <button
            :for={
              {section, label, icon} <- [
                {"agenda", "Agenda", "hero-calendar-days"},
                {"devoirs", "Devoirs", "hero-pencil-square"},
                {"notes", "Notes", "hero-academic-cap"},
                {"cantine", "Menu", "utensils"}
              ]
            }
            id={"nav-#{section}"}
            phx-click="section"
            phx-value-section={section}
            disabled={@loading}
            aria-current={
              if @section == section || (@section == "timetable" && section == "agenda"), do: "page"
            }
            class="navigation-tab"
          >
            <.icon name={icon} class="navigation-tab-icon size-4" />
            {label}
            <.count_badge
              :if={section == "devoirs" && @homework_badge_count > 0}
              id="homework-nav-badge"
              data-expanded={to_string(@homework_badge_count > 9)}
              aria-label={
              "#{@homework_badge_count} devoirs à faire " <>
                if(Date.day_of_week(@today) == 6, do: "d’ici lundi", else: "pour aujourd’hui et demain")
            }
              count={@homework_badge_count}
            />
          </button>
        </nav>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp avatar_src(child), do: Pronotex.Family.avatar(child)
  defp first_name(child), do: Pronotex.Family.first_name(child)

  defp messages_label(%{role: :parent, label: name}, _child, "parent-messages"),
    do: "Messages " <> name

  defp messages_label(%{role: :parent}, child, "messages") when not is_nil(child),
    do: "Messages " <> first_name(child)

  defp messages_label(_, _, _), do: "Messages"
end
