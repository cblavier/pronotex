defmodule Pronotex.Accounts do
  @moduledoc "Login profiles. Only public profile metadata leaves this module."

  def all do
    specs()
    |> Enum.filter(&configured?/1)
    |> Enum.map(&Map.take(&1, [:id, :role, :label, :prefix]))
  end

  def get(id), do: Enum.find(all(), &(&1.id == id))
  def pin(id), do: field(id, :pin)
  def credentials(id), do: {field(id, :username), field(id, :password)}

  def fingerprint(id) do
    case Enum.find(specs(), &(&1.id == id)) do
      nil -> nil
      spec -> :crypto.hash(:sha256, :erlang.term_to_binary({spec, System.get_env("PRONOTE_URL")}))
    end
  end

  defp field(id, key) do
    case Enum.find(specs(), &(&1.id == id)) do
      nil -> nil
      spec -> Map.get(spec, key)
    end
  end

  defp configured?(spec) do
    is_binary(spec.pin) and Regex.match?(~r/\A[0-9]{8}\z/, spec.pin) and
      spec.username not in [nil, ""] and spec.password not in [nil, ""] and
      spec.label not in [nil, ""]
  end

  defp specs do
    Application.get_env(:pronotex, :accounts) || from_env()
  end

  defp from_env do
    numbered =
      System.get_env()
      |> Map.keys()
      |> Enum.flat_map(fn key ->
        case Regex.run(~r/^PRONOTE_(PARENT|CHILD)_([1-9][0-9]*)_USERNAME$/, key) do
          [_, role, number] -> [{role, String.to_integer(number)}]
          _ -> []
        end
      end)
      |> Enum.sort_by(fn {role, number} -> {if(role == "CHILD", do: 0, else: 1), number} end)
      |> Enum.map(fn {role, number} ->
        prefix = "PRONOTE_#{role}_#{number}"

        profile(
          String.downcase(role) <> "-#{number}",
          if(role == "CHILD", do: :child, else: :parent),
          prefix,
          System.get_env(prefix <> "_FIRST_NAME")
        )
      end)

    [profile("family", :family, "PRONOTE_FAMILY", "Famille") | numbered]
  end

  defp profile(id, role, prefix, label) do
    %{
      id: id,
      role: role,
      prefix: prefix,
      label: label,
      pin: System.get_env(prefix <> "_PIN_CODE"),
      username: System.get_env(prefix <> "_USERNAME"),
      password: System.get_env(prefix <> "_PASSWORD")
    }
  end
end
