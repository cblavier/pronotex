defmodule Pronotex.Pronote.Session do
  @moduledoc "Serializes PRONOTE's numbered requests. Connects only when first used."
  use GenServer
  alias Pronotex.Pronote.{Client, Config, Error}

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: Keyword.get(options, :name, __MODULE__))
  end

  @impl true
  def init(options), do: {:ok, %{options: options, client: nil, students: %{}}}

  @impl true
  def handle_call(:logout, _from, state), do: {:reply, :ok, %{state | client: nil, students: %{}}}

  # Never retry a write automatically: its outcome may be unknown after a network error.
  def handle_call({:set_homework_done, _, _, _}, _from, %{client: nil} = state),
    do: {:reply, {:error, Error.new(:stale_homework)}, state}

  def handle_call({:set_homework_done, _, _, _} = operation, _from, state) do
    case safely(fn -> execute(operation, state) end) do
      {:ok, reply, state} ->
        {:reply, {:ok, reply}, state}

      {:error, error} ->
        {:reply, {:error, error}, %{state | students: %{}, client: nil}}
    end
  end

  def handle_call(operation, _from, state) do
    case safely(fn -> execute(operation, state) end) do
      {:ok, reply, state} ->
        {:reply, {:ok, reply}, state}

      {:error, %Error{reason: :session_expired}} ->
        # Reconnect once and reconstruct the full read with fresh child resources.
        case safely(fn -> execute(operation, %{state | client: nil}) end) do
          {:ok, reply, state} -> {:reply, {:ok, reply}, state}
          {:error, error} -> {:reply, {:error, error}, %{state | client: nil}}
        end

      {:error, error} ->
        {:reply, {:error, error}, %{state | client: nil}}
    end
  end

  @impl true
  def format_status(status), do: %{status | state: :redacted}

  defp execute(operation, %{client: nil} = state) do
    config =
      case Keyword.get(state.options, :config) do
        nil -> Config.from_env()
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
    {lessons, client} = Client.lessons(state.client, child_id, from, to)
    {:ok, lessons, %{state | client: client}}
  end

  defp execute({:homework, child_id, from, to}, state) do
    {homework, client} = Client.homework(state.client, child_id, from, to)
    {:ok, homework, %{state | client: client}}
  end

  defp execute({:menus, child_id, from, to}, state) do
    {menus, client} = Client.menus(state.client, child_id, from, to)
    {:ok, menus, %{state | client: client}}
  end

  defp execute({:grades, child_id, period_name}, state) do
    {grades, client} = Client.grades(state.client, child_id, period_name)
    {:ok, grades, %{state | client: client}}
  end

  defp execute({:events, child_id}, state) do
    {events, client} = Client.events(state.client, child_id)
    {:ok, events, %{state | client: client}}
  end

  defp execute({:set_homework_done, child_id, homework_id, done}, state) do
    child = Enum.find(Client.children(state.client), &(&1.id == child_id))
    unless child, do: raise(Error.new(:child_not_found))

    config_result =
      case Keyword.get(state.options, :student_configs) do
        nil ->
          Config.student_from_env(child)

        configs ->
          case Map.fetch(configs, child_id) do
            {:ok, config} -> Config.validate(config)
            :error -> {:error, Error.new(:student_credentials_required)}
          end
      end

    config =
      case config_result do
        {:ok, config} -> config
        _ -> raise Error.new(:student_credentials_required)
      end

    {from, to} =
      Map.get(state.client.homework_reads, {child_id, homework_id}) ||
        raise(Error.new(:stale_homework))

    {tasks, parent} = Client.homework(state.client, child_id, from, to)
    target = Enum.find(tasks, &(&1.id == homework_id)) || raise(Error.new(:stale_homework))
    cached = Map.get(state.students, child_id)

    student =
      case cached do
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

    [identity] = Client.children(student)

    unless normalize_name(identity.name) == normalize_name(child.name),
      do: raise(Error.new(:student_mismatch))

    {student_tasks, student} = Client.homework(student, identity.id, from, to)

    matches =
      Enum.filter(
        student_tasks,
        &(&1.date == target.date and &1.subject == target.subject and
            &1.description == target.description)
      )

    student_task =
      case matches do
        [task] -> task
        _ -> raise Error.new(:stale_homework)
      end

    {_, student} = Client.set_homework_done(student, identity.id, student_task.id, done)

    tasks =
      Enum.map(tasks, fn task ->
        if task.id == homework_id, do: %{task | done: done}, else: task
      end)

    {:ok, tasks,
     %{state | client: parent, students: Map.put(state.students, child_id, {config, student})}}
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
