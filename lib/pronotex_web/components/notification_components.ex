defmodule PronotexWeb.NotificationComponents do
  use PronotexWeb, :html

  attr :notifications, :list, required: true
  attr :children, :list, required: true

  def notification_banners(assigns) do
    assigns = assign(assigns, :banners, banners(assigns.notifications, assigns.children))

    ~H"""
    <section
      id="notification-banners"
      aria-label="Notifications"
    >
      <.notification_banner :for={banner <- @banners} banner={banner} />
    </section>
    """
  end

  attr :banner, :map, required: true

  def notification_banner(assigns) do
    ~H"""
    <div
      class="notification-banner"
      data-notification-tag={@banner.tag}
      data-child-theme={@banner.theme}
    >
      <span class="notification-avatar" role="img" aria-label={@banner.name}>
        <img :if={@banner.avatar} src={@banner.avatar} alt="" />
        <span :if={!@banner.avatar}>{String.first(@banner.name)}</span>
      </span>
      <span class="notification-title">{@banner.title}</span>
      <.button
        class="btn btn-sm btn-soft themed-mini-button"
        type="button"
        phx-click="view-notification"
        phx-value-tag={@banner.tag}
        aria-label={"Voir : #{@banner.title} de #{@banner.name}"}
      >
        Voir
      </.button>
      <button
        type="button"
        phx-click="dismiss-notification"
        phx-value-tag={@banner.tag}
        aria-label={"Fermer : #{@banner.title} de #{@banner.name}"}
      >
        <.icon name="hero-x-mark" class="size-4" />
      </button>
    </div>
    """
  end

  defp banners(notifications, children) do
    Enum.flat_map(notifications, fn notification ->
      uri = URI.parse(notification["url"])

      child =
        Enum.find(children, fn child ->
          slug =
            child
            |> Pronotex.Family.first_name()
            |> String.trim()
            |> String.downcase()
            |> String.replace(~r/\s+/u, "-")
            |> URI.encode(&URI.char_unreserved?/1)

          path = "/" <> slug <> if(notification["kind"] == "grades", do: "/notes", else: "")
          is_nil(uri.scheme) and is_nil(uri.host) and uri.path == path
        end)

      if child do
        [
          %{
            tag: notification["tag"],
            url: notification["url"],
            title:
              if(notification["kind"] == "grades",
                do: "Nouvelles notes",
                else: "Annulation de cours"
              ),
            name: Pronotex.Family.first_name(child),
            avatar: Pronotex.Family.avatar(child),
            theme: Pronotex.Family.theme(children, child)
          }
        ]
      else
        []
      end
    end)
  end
end
