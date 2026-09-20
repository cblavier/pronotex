defmodule Pronotex.Pronote do
  @moduledoc """
  PRONOTE reads and explicit status updates, serialized in isolated profile sessions.

      {:ok, children} = Pronotex.Pronote.children()
      {:ok, lessons} = Pronotex.Pronote.lessons(hd(children).id, ~D[2026-09-14], ~D[2026-09-20])

  Credentials are read from the selected numbered profile or PRONOTE_FAMILY
  at first use, not on Phoenix startup. Homework and discussion statuses change only through their explicit write functions.
  """
  alias Pronotex.Pronote.{Error, Session}

  def parent_discussions(server), do: GenServer.call(server, {:parent_discussions}, :infinity)

  def set_parent_discussion_read(id, read, server) when is_boolean(read),
    do: GenServer.call(server, {:set_parent_discussion_read, id, read}, :infinity)

  def homework_writable?(child), do: Pronotex.Pronote.Config.student_configured?(child)

  def login(server \\ Session), do: GenServer.call(server, :login, :infinity)
  def children(server \\ Session), do: GenServer.call(server, :children, :infinity)
  def logout(server \\ Session), do: GenServer.call(server, :logout)

  @doc "Reads an inclusive date range. Each lesson retains its child ID and local school times."
  def lessons(child_id, from, to, server \\ Session)

  def lessons(child_id, %Date{} = from, %Date{} = to, server) when is_binary(child_id) do
    if Date.diff(to, from) in 0..365 do
      GenServer.call(server, {:lessons, child_id, from, to}, :infinity)
    else
      {:error, Error.new(:invalid_dates)}
    end
  end

  def lessons(_, _, _, _), do: {:error, Error.new(:invalid_dates)}
  @doc "Reads homework due within the inclusive date range, without marking anything done."
  def homework(child_id, from, to, server \\ Session)

  def homework(child_id, %Date{} = from, %Date{} = to, server) when is_binary(child_id) do
    if Date.diff(to, from) in 0..365 do
      GenServer.call(server, {:homework, child_id, from, to}, :infinity)
    else
      {:error, Error.new(:invalid_dates)}
    end
  end

  def homework(_, _, _, _), do: {:error, Error.new(:invalid_dates)}
  @doc "Reads published canteen menus within an inclusive date range."
  def menus(child_id, from, to, server \\ Session)

  def menus(child_id, %Date{} = from, %Date{} = to, server) when is_binary(child_id) do
    if Date.diff(to, from) in 0..365 do
      GenServer.call(server, {:menus, child_id, from, to}, :infinity)
    else
      {:error, Error.new(:invalid_dates)}
    end
  end

  def menus(_, _, _, _), do: {:error, Error.new(:invalid_dates)}
  @doc "Reads marks and published averages for a child's period (default: current period)."
  def grades(child_id, period_name \\ nil, server \\ Session) do
    GenServer.call(server, {:grades, child_id, period_name}, :infinity)
  end

  @doc "Reads upcoming school agenda events, including events shared with the family."
  def events(child_id, server \\ Session),
    do: GenServer.call(server, {:events, child_id}, :infinity)

  def discussions(child_id, server \\ Session),
    do: GenServer.call(server, {:discussions, child_id}, :infinity)

  def set_discussion_read(child_id, id, read, server \\ Session) when is_boolean(read),
    do: GenServer.call(server, {:set_discussion_read, child_id, id, read}, :infinity)

  @doc "Sets a previously read homework status and verifies it by reading Pronote again."
  def set_homework_done(child_id, homework_id, done, server \\ Session)

  def set_homework_done(child_id, homework_id, done, server)
      when is_binary(child_id) and is_binary(homework_id) and is_boolean(done),
      do: GenServer.call(server, {:set_homework_done, child_id, homework_id, done}, :infinity)

  def set_homework_done(_, _, _, _), do: {:error, Error.new(:invalid_homework)}
end
