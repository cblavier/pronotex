defmodule PronotexWeb.ContentComponents do
  use PronotexWeb, :html

  attr :id, :string, default: nil
  attr :tag, :string, default: "article", values: ~w(article section aside)
  attr :class, :any, default: nil
  attr :title_tag, :string, default: "h3", values: ~w(h2 h3 h4)
  attr :title_id, :string, default: nil
  attr :body_class, :any, default: nil
  attr :rest, :global
  attr :truncate_title, :boolean, default: false
  slot :title, required: true
  slot :title_badge
  slot :subtitle
  slot :date
  slot :actions
  slot :inner_block, required: true

  def content_card(assigns) do
    ~H"""
    <.dynamic_tag tag_name={@tag} id={@id} class={["content-card day-group", @class]} {@rest}>
      <.content_card_header
        title_tag={@title_tag}
        title_id={@title_id}
        truncate_title={@truncate_title}
      >
        <:title>{render_slot(@title)}</:title>
        <:title_badge :if={@title_badge != []}>{render_slot(@title_badge)}</:title_badge>
        <:subtitle :if={@subtitle != []}>{render_slot(@subtitle)}</:subtitle>
        <:date :if={@date != []}>{render_slot(@date)}</:date>
        <:actions :if={@actions != []}>{render_slot(@actions)}</:actions>
      </.content_card_header>
      <div class={["content-card-body", @body_class]}>{render_slot(@inner_block)}</div>
    </.dynamic_tag>
    """
  end

  attr :class, :any, default: nil
  attr :title_tag, :string, default: "h3", values: ~w(h2 h3 h4)
  attr :title_id, :string, default: nil
  attr :truncate_title, :boolean, default: false
  slot :title, required: true
  slot :title_badge
  slot :subtitle
  slot :date
  slot :actions

  def content_card_header(assigns) do
    ~H"""
    <header
      class={["content-card-header day-heading", @class]}
      data-truncate-title={to_string(@truncate_title)}
    >
      <.dynamic_tag tag_name={@title_tag} id={@title_id} class="content-card-title">
        <%= if @truncate_title do %>
          <span class="content-card-title-text">{render_slot(@title)}</span>
        <% else %>
          {render_slot(@title)}
        <% end %>
        <span :if={@title_badge != []} class="content-card-title-badge">
          {render_slot(@title_badge)}
        </span>
      </.dynamic_tag>
      <div :if={@date != []} class="content-card-date">{render_slot(@date)}</div>
      <div :if={@actions != []} class="content-card-actions">{render_slot(@actions)}</div>
      <div :if={@subtitle != []} class="content-card-subtitle">{render_slot(@subtitle)}</div>
    </header>
    """
  end
end
