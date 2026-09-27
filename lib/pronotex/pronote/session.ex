defmodule Pronotex.Pronote.Session do
  @moduledoc "Serializes PRONOTE's numbered requests. Connects only when first used."
  use GenServer
  alias Pronotex.Pronote.{Client, Config, Error, ReadCache}

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: Keyword.get(options, :name, __MODULE__))
  end

  def for_account(id) do
    if is_nil(Pronotex.Accounts.get(id)), do: raise(Error.new(:forbidden))
    name = {:via, Registry, {Pronotex.Pronote.Registry, {id, Pronotex.Accounts.fingerprint(id)}}}

    case DynamicSupervisor.start_child(
           Pronotex.Pronote.Supervisor,
           {__MODULE__, [name: name, account: id]}
         ) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
      {:error, _} -> raise Error.new(:network)
    end
  end

  @impl true
  def init(options), do: {:ok, %{options: options, client: nil, students: %{}}}

  @impl true
  def handle_call(:clear_cache, _from, state) do
    ReadCache.invalidate(self())
    {:reply, :ok, state}
  end

  def handle_call(operation, from, state) do
    affected =
      case operation do
        {:set_homework_done, _, _, _} -> :homework
        {:set_discussion_read, _, _, _} -> :discussions
        {:set_parent_discussion_read, _, _} -> :parent_discussions
        _ -> nil
      end

    if affected, do: ReadCache.invalidate({:kind, affected})

    try do
      result = handle_operation(operation, from, state)

      if operation == :logout or match?({:reply, {:error, _}, _}, result),
        do: ReadCache.invalidate(self())

      result
    after
      # Even an uncertain write may have reached PRONOTE. Also discard reads
      # that started before or during the write in another profile.
      if affected, do: ReadCache.invalidate({:kind, affected})
    end
  end

  defp handle_operation(:logout, _from, state),
    do: {:reply, :ok, %{state | client: nil, students: %{}}}

  defp handle_operation(operation, _from, state)
       when elem(operation, 0) in [
              :discussions,
              :set_discussion_read,
              :parent_discussions,
              :set_parent_discussion_read
            ] do
    result = safely(fn -> execute(operation, state) end)

    result =
      case result do
        {:error, %Error{reason: :session_expired}}
        when elem(operation, 0) in [:discussions, :parent_discussions] ->
          safely(fn -> execute(operation, %{state | students: %{}, client: nil}) end)

        other ->
          other
      end

    case result do
      {:ok, reply, updated} -> {:reply, {:ok, reply}, updated}
      {:error, error} -> {:reply, {:error, error}, %{state | students: %{}}}
    end
  end

  # Never retry a write automatically: its outcome may be unknown after a network error.
  defp handle_operation({:set_homework_done, _, _, _}, _from, %{client: nil} = state),
    do: {:reply, {:error, Error.new(:stale_homework)}, state}

  defp handle_operation({:set_homework_done, _, _, _} = operation, _from, state) do
    case safely(fn -> execute(operation, state) end) do
      {:ok, reply, state} ->
        {:reply, {:ok, reply}, state}

      {:error, error} ->
        {:reply, {:error, error}, %{state | students: %{}, client: nil}}
    end
  end

  defp handle_operation(operation, _from, state) do
    case safely(fn -> execute(operation, state) end) do
      {:ok, reply, state} ->
        {:reply, {:ok, reply}, state}

      {:error, %Error{reason: :session_expired}} ->
        # Reconnect once and reconstruct the full read with fresh child resources.
        case safely(fn -> execute(operation, %{state | client: nil, students: %{}}) end) do
          {:ok, reply, state} -> {:reply, {:ok, reply}, state}
          {:error, error} -> {:reply, {:error, error}, %{state | client: nil, students: %{}}}
        end

      {:error, %Error{reason: reason, code: nil} = error}
      when reason in [:child_not_found, :outside_school_year, :forbidden] and
             not is_nil(state.client) ->
        # These validations run before any request: the numbered session is still valid.
        # Dropping it would invalidate the child IDs held by the other dashboard reads.
        {:reply, {:error, error}, state}

      {:error, error} ->
        {:reply, {:error, error}, %{state | client: nil, students: %{}}}
    end
  end

  @impl true
  def format_status(status), do: %{status | state: :redacted}

  defp execute(operation, %{client: nil} = state) do
    ReadCache.invalidate(self())

    config =
      case Keyword.get(state.options, :config) do
        nil -> Config.from_account(Keyword.get(state.options, :account, "family"))
        config -> Config.validate(config)
      end

    case config do
      {:ok, config} ->
        client = Client.login(config, Keyword.get(state.options, :req_options, []))
        execute(operation, %{state | client: client})

      {:error, error} ->
        raise error
    end
  end

  defp execute(operation, state) when operation in [:login, :children],
    do: {:ok, Client.children(state.client), state}

  defp execute({:lessons, child_id, from, to}, state) do
    {lessons, client} =
      cached_read(
        state.client,
        {:lessons, child_id, from, to},
        Keyword.get(state.options, :account, "family")
      )

    {:ok, lessons, %{state | client: client}}
  end

  defp execute({:homework, child_id, from, to}, state) do
    child = Enum.find(Client.children(state.client), &(&1.id == child_id))
    unless child, do: raise(Error.new(:child_not_found))

    # Resource IDs are session-specific. Read writable homework in the same
    # student session that will submit the status, including identical assignments.
    if state.client.transport.space != 3 and match?({:ok, _}, student_config(state, child)) do
      {config, student} = student_client(state, child_id)
      [identity] = Client.children(student)
      {homework, student} = cached_read(student, {:homework, identity.id, from, to})
      homework = Enum.map(homework, &%{&1 | child_id: child_id})
      {:ok, homework, %{state | students: Map.put(state.students, child_id, {config, student})}}
    else
      {homework, client} = cached_read(state.client, {:homework, child_id, from, to})
      {:ok, homework, %{state | client: client}}
    end
  end

  defp execute({:menus, child_id, from, to}, state) do
    {menus, client} = cached_read(state.client, {:menus, child_id, from, to})
    {:ok, menus, %{state | client: client}}
  end

  defp execute({:grades, child_id, period_name}, state) do
    {grades, client} =
      cached_read(
        state.client,
        {:grades, child_id, period_name},
        Keyword.get(state.options, :account, "family")
      )

    history = average_history(client, child_id, grades)
    grades = Map.update!(grades, :grades, &grades_by_publication(client, child_id, grades, &1))
    {:ok, Map.put(grades, :average_history, history), %{state | client: client}}
  end

  defp execute({:events, child_id}, state) do
    {events, client} = cached_read(state.client, {:events, child_id})
    {:ok, events, %{state | client: client}}
  end

  defp execute({:parent_discussions}, state) do
    authorize_parent!(state)
    {reply, client} = cached_read(state.client, {:parent_discussions})
    {:ok, reply, %{state | client: client}}
  end

  defp execute({:set_parent_discussion_read, id, read}, state) do
    authorize_parent!(state)
    {reply, client} = Client.set_discussion_read(state.client, id, read)
    {:ok, reply, %{state | client: client}}
  end

  defp execute(operation, %{client: %{transport: %{space: 3}}} = state)
       when elem(operation, 0) in [:discussions, :set_discussion_read, :set_homework_done] do
    child_id = elem(operation, 1)

    unless Enum.any?(Client.children(state.client), &(&1.id == child_id)),
      do: raise(Error.new(:child_not_found))

    {reply, client} =
      case operation do
        {:discussions, _} ->
          cached_read(state.client, operation)

        {:set_discussion_read, _, id, read} ->
          Client.set_discussion_read(state.client, id, read)

        {:set_homework_done, _, id, done} ->
          Client.set_homework_done(state.client, child_id, id, done)
      end

    {:ok, reply, %{state | client: client}}
  end

  defp execute(operation, state)
       when elem(operation, 0) in [:discussions, :set_discussion_read] do
    child_id = elem(operation, 1)
    {config, student} = student_client(state, child_id)

    {reply, student} =
      case operation do
        {:discussions, _} -> cached_read(student, operation)
        {:set_discussion_read, _, id, read} -> Client.set_discussion_read(student, id, read)
      end

    {:ok, reply, %{state | students: Map.put(state.students, child_id, {config, student})}}
  end

  defp execute({:set_homework_done, child_id, homework_id, done}, state) do
    {config, student} = student_client(state, child_id)
    [identity] = Client.children(student)
    {tasks, student} = Client.set_homework_done(student, identity.id, homework_id, done)
    tasks = Enum.map(tasks, &%{&1 | child_id: child_id})
    {:ok, tasks, %{state | students: Map.put(state.students, child_id, {config, student})}}
  end

  defp student_client(state, child_id) do
    child = Enum.find(Client.children(state.client), &(&1.id == child_id))
    unless child, do: raise(Error.new(:child_not_found))

    config_result = student_config(state, child)

    config =
      case config_result do
        {:ok, config} -> config
        _ -> raise Error.new(:student_credentials_required)
      end

    student =
      case Map.get(state.students, child_id) do
        {^config, client} ->
          client

        _ ->
          Client.login(
            config,
            Keyword.get(
              state.options,
              :student_req_options,
              Keyword.get(state.options, :req_options, [])
            )
          )
      end

    case Client.children(student) do
      [identity] ->
        unless normalize_name(identity.name) == normalize_name(child.name),
          do: raise(Error.new(:student_mismatch))

      _ ->
        raise(Error.new(:student_mismatch))
    end

    {config, student}
  end

  defp student_config(state, child) do
    child_id = child.id

    case Keyword.get(state.options, :student_configs) do
      nil ->
        Config.student_from_env(child)

      configs ->
        case Map.fetch(configs, child_id) do
          {:ok, config} -> Config.validate(config)
          :error -> {:error, Error.new(:student_credentials_required)}
        end
    end
  end

  defp cached_read(client, operation, account_id \\ nil) do
    # Never cache or restore a Client: its ordered transport and write-validation
    # state must remain the current state of this serialized session.
    transport = client.transport

    identity =
      {transport.root, transport.session, transport.space, transport.key, client.children,
       client.tabs}

    key = {self(), {:crypto.hash(:sha256, :erlang.term_to_binary(identity)), operation}}

    case ReadCache.fetch(key) do
      {:hit, reply} ->
        {reply, client}

      {:miss, generation} ->
        [kind | args] = Tuple.to_list(operation)

        {function, args} =
          if kind in [:discussions, :parent_discussions],
            do: {:discussions, []},
            else: {kind, args}

        {reply, updated} = apply(Client, function, [client | args])

        if persist_read(updated, operation, reply, account_id) == :ok do
          ReadCache.put(key, reply, ReadCache.ttl(kind), generation)
        end

        {reply, updated}
    end
  end

  defp grades_by_publication(client, child_id, report, grades) do
    client
    |> Pronotex.GradeHistory.context(child_id, report)
    |> Pronotex.GradeHistory.by_publication(grades)
  rescue
    _ ->
      require Logger
      Logger.warning("Unable to read grade publication history")
      grades
  end

  defp average_history(client, child_id, report) do
    client |> Pronotex.GradeHistory.context(child_id, report) |> Pronotex.GradeHistory.averages()
  rescue
    _ ->
      require Logger
      Logger.warning("Unable to read official average history")
      []
  end

  defp persist_read(client, {:grades, child_id, _period}, report, account_id) do
    context = Pronotex.GradeHistory.context(client, child_id, report)

    {:ok, _} =
      Pronotex.GradeHistory.record(context, report, DateTime.utc_now(),
        legacy_context: %{context | student_id: child_id}
      )

    children = Client.children(client)
    child = Enum.find(children, &(&1.id == child_id))
    # Ambiguous full names are not safe durable identities for notifications.
    if child && Enum.count(children, &(&1.name == child.name)) == 1 do
      {:ok, _} = Pronotex.Push.observe(account_id, context, child, report)
    end

    :ok
  rescue
    _ ->
      # A storage failure must not roll back the already advanced PRONOTE transport.
      # Do not cache this response: the next read will retry the observation.
      require Logger
      Logger.error("Unable to persist PRONOTE grade history; next fresh read will retry")
      :error
  end

  defp persist_read(client, {:lessons, child_id, _from, _to}, lessons, account_id) do
    children = Client.children(client)
    child = Enum.find(children, &(&1.id == child_id))

    if child && Enum.count(children, &(&1.name == child.name)) == 1 do
      context = %{
        school_url: client.transport.root,
        school_year: client.general["PremierLundi"]["V"]
      }

      {:ok, _} = Pronotex.Push.observe_cancellations(account_id, context, child, lessons)
    end

    :ok
  rescue
    _ ->
      require Logger
      Logger.error("Unable to persist PRONOTE cancellations; next fresh read will retry")
      :error
  end

  defp persist_read(_client, _operation, _reply, _account_id), do: :ok

  defp authorize_parent!(state) do
    unless match?(%{role: :parent}, Pronotex.Accounts.get(Keyword.get(state.options, :account))),
      do: raise(Error.new(:forbidden))
  end

  defp normalize_name(name),
    do: name |> String.downcase() |> String.split() |> Enum.sort() |> Enum.join(" ")

  defp safely(fun) do
    try do
      fun.()
    rescue
      error in Error -> {:error, error}
      # Parsing errors may contain private response fragments; never propagate them.
      _ -> {:error, Error.new(:protocol)}
    end
  end
end
