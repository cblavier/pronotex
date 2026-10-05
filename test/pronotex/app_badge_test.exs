defmodule Pronotex.AppBadgeTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Pronotex.{AppBadge, NotificationBanners, Repo}
  alias Pronotex.Push.Setting

  setup do
    Repo.delete_all(from(s in Setting, where: like(s.key, "app-badge:%")))

    for account <- ["parent-1", "child-1", "family"],
        banner <- NotificationBanners.list(account),
        do: NotificationBanners.dismiss(account, banner["tag"])

    :ok
  end

  test "only the profile's personal inbox controls the icon" do
    assert AppBadge.count("parent-1") == nil
    AppBadge.observe("parent-1", {:parent_discussions}, [%{unread: 0}])
    AppBadge.observe("parent-1", {:discussions, "child"}, [%{unread: 2}])
    assert AppBadge.count("parent-1") == 0
    AppBadge.observe("parent-1", {:parent_discussions}, [%{unread: 1}])
    assert AppBadge.count("parent-1") == 1
    AppBadge.observe("parent-1", {:set_discussion_read, "child", "thread", true}, [])
    assert AppBadge.count("parent-1") == 1
    AppBadge.observe("parent-1", {:set_parent_discussion_read, "thread", true}, [%{unread: 0}])
    assert AppBadge.count("parent-1") == 0
    AppBadge.observe("child-1", {:discussions, "child"}, [%{unread: 1}])
    assert AppBadge.count("child-1") == 1
    AppBadge.observe("family", {:discussions, "child"}, [%{unread: 1}])
    assert AppBadge.count("family") == 0
  end

  test "the badge remains until both the personal inbox and banners are cleared" do
    AppBadge.observe("parent-1", {:parent_discussions}, [%{unread: 1}])
    NotificationBanners.activate("parent-1", "grades", "/alice/notes")
    [banner] = NotificationBanners.list("parent-1")
    AppBadge.observe("parent-1", {:set_parent_discussion_read, "thread", true}, [])
    assert AppBadge.count("parent-1") == 1
    NotificationBanners.dismiss("parent-1", banner["tag"])
    assert AppBadge.count("parent-1") == 0
    NotificationBanners.activate("family", "cancellation", "/alice")
    assert AppBadge.count("family") == 1
  end

  test "counts unread messages plus each outstanding banner without accumulating refreshes" do
    inbox = [%{unread: 3}, %{unread: 2}, %{unread: 0}]
    AppBadge.observe("parent-1", {:parent_discussions}, inbox)
    NotificationBanners.activate("parent-1", "grades", "/alice/notes")
    NotificationBanners.activate("parent-1", "cancellation", "/marius")
    assert AppBadge.count("parent-1") == 7
    AppBadge.observe("parent-1", {:parent_discussions}, inbox)
    NotificationBanners.activate("parent-1", "grades", "/alice/notes")
    assert AppBadge.count("parent-1") == 7
    AppBadge.observe("parent-1", {:set_parent_discussion_read, "thread", true}, [%{unread: 2}])
    assert AppBadge.count("parent-1") == 4
    [banner | _] = NotificationBanners.list("parent-1")
    NotificationBanners.dismiss("parent-1", banner["tag"])
    assert AppBadge.count("parent-1") == 3
  end
end
