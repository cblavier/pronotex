defmodule Pronotex.NotificationBannersTest do
  use ExUnit.Case, async: false
  alias Pronotex.NotificationBanners, as: Banners

  setup do
    start_supervised!({Banners, name: __MODULE__})
    :ok
  end

  test "new detections replace a banner without allowing stale or foreign acknowledgements" do
    Banners.subscribe("family")
    Banners.activate("family", "grades", "/alice/notes?period=s1", __MODULE__)
    assert_receive :notification_banners_changed
    [old] = Banners.list("family", __MODULE__)
    Banners.activate("family", "grades", "/alice/notes?period=s2", __MODULE__)
    [new] = Banners.list("family", __MODULE__)
    assert new["tag"] != old["tag"]
    assert new["url"] == "/alice/notes?period=s2"
    Banners.dismiss("family", old["tag"], __MODULE__)
    Banners.dismiss("parent-1", new["tag"], __MODULE__)
    assert Banners.list("family", __MODULE__) == [new]
    assert Banners.list("parent-1", __MODULE__) == []
    Banners.dismiss("family", new["tag"], __MODULE__)
    assert Banners.list("family", __MODULE__) == []
  end

  test "a process restart loses unread banners" do
    Banners.activate("family", "grades", "/alice/notes", __MODULE__)
    assert [_] = Banners.list("family", __MODULE__)
    stop_supervised!(Banners)
    start_supervised!({Banners, name: __MODULE__})
    assert Banners.list("family", __MODULE__) == []
  end
end
