defmodule Pronotex.AppBadge do
  @moduledoc "The app icon reflects personal unread messages and outstanding banners."
  alias Pronotex.{Accounts, NotificationBanners, Repo}
  alias Pronotex.Push.Setting

  def observe(account_id, operation, discussions) do
    role =
      case Accounts.get(account_id) do
        nil -> nil
        account -> account.role
      end

    personal? =
      case operation do
        {kind} when kind == :parent_discussions -> role == :parent
        {:set_parent_discussion_read, _, _} -> role == :parent
        {:discussions, _} -> role == :child
        {:set_discussion_read, _, _, _} -> role == :child
        _ -> false
      end

    if personal? do
      value = %{"unread" => Enum.sum(Enum.map(discussions, &max(&1.unread, 0)))}

      Repo.insert!(%Setting{key: key(account_id), value: value},
        on_conflict: [set: [value: value]],
        conflict_target: :key
      )
    end

    :ok
  end

  # Unknown is distinct from read: a failed/unfinished initial sync must not clear a badge.
  def count(account_id) do
    banners = length(NotificationBanners.list(account_id))

    unread =
      case Accounts.get(account_id) do
        %{role: :family} ->
          0

        nil ->
          0

        _ ->
          case Repo.get(Setting, key(account_id)) do
            nil -> nil
            setting -> unread_count(setting.value["unread"])
          end
      end

    if is_integer(unread), do: unread + banners, else: if(banners > 0, do: banners, else: nil)
  end

  # Preserve the previous indicator until the next inbox synchronization.
  defp unread_count(true), do: 1
  defp unread_count(false), do: 0
  defp unread_count(count) when is_integer(count) and count >= 0, do: count
  defp unread_count(_), do: nil

  defp key(account_id),
    do: "app-badge:" <> account_id <> ":" <> Base.url_encode64(Accounts.fingerprint(account_id))
end
