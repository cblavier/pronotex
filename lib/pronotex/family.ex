defmodule Pronotex.Family do
  @moduledoc "Optional per-child customization from numbered environment variables."

  def first_name(%{first_name: name}) when is_binary(name) and name != "", do: name

  def first_name(child) do
    words = String.split(child.name)
    given = Enum.drop_while(words, &(&1 == String.upcase(&1)))

    case {words, given} do
      {[], _} -> "Enfant"
      {_, []} -> List.last(words)
      {^given, _} -> hd(words)
      {_, names} -> Enum.join(names, " ")
    end
  end

  def prefix(nil), do: nil

  def prefix(child) do
    matches =
      System.get_env()
      |> Enum.filter(fn {key, value} ->
        Regex.match?(~r/^PRONOTE_CHILD_[1-9][0-9]*_FIRST_NAME$/, key) and
          normalize(value) == normalize(first_name(child))
      end)

    case matches do
      [{key, _}] -> String.replace_suffix(key, "_FIRST_NAME", "")
      _ -> nil
    end
  end

  def value(child, suffix) do
    case prefix(child) do
      nil ->
        nil

      prefix ->
        case System.get_env(prefix <> "_" <> suffix) do
          value when value in [nil, ""] -> nil
          value -> value
        end
    end
  end

  def theme(children, child) do
    index = Enum.find_index(children, &(&1.id == child.id)) || 0

    case value(child, "THEME") do
      theme when theme in ["blue", "green"] -> theme
      _ -> if rem(index, 2) == 0, do: "blue", else: "green"
    end
  end

  def avatar(child) do
    prefix = prefix(child)

    if prefix &&
         match?({:ok, _, _}, avatar_data(String.replace_prefix(prefix, "PRONOTE_CHILD_", ""))) do
      "/avatars/" <> String.replace_prefix(prefix, "PRONOTE_CHILD_", "")
    else
      local_avatar(child)
    end
  end

  def avatar_data(index) when is_binary(index) do
    with true <- Regex.match?(~r/^[1-9][0-9]{0,5}$/, index),
         encoded when is_binary(encoded) <- System.get_env("PRONOTE_CHILD_#{index}_AVATAR_BASE64"),
         true <- byte_size(encoded) <= 262_144,
         {:ok, bytes} <- Base.decode64(encoded, ignore: :whitespace),
         type when not is_nil(type) <- image_type(bytes) do
      {:ok, type, bytes}
    else
      _ -> :error
    end
  end

  defp image_type(<<137, 80, 78, 71, 13, 10, 26, 10, _::binary>>), do: "image/png"
  defp image_type(<<255, 216, 255, _::binary>>), do: "image/jpeg"
  defp image_type(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: "image/webp"
  defp image_type(_), do: nil

  defp local_avatar(child) do
    case value(child, "AVATAR") do
      "/images/avatars/" <> file = path ->
        if file != "" and not String.contains?(file, ["..", "\\", "?", "#"]), do: path

      _ ->
        nil
    end
  end

  defp normalize(value), do: value |> String.trim() |> String.downcase() |> String.normalize(:nfc)
end
