defmodule Pronotex.Pronote.Color do
  @moduledoc false

  def parse(value) when is_binary(value) do
    if Regex.match?(~r/\A#[0-9a-fA-F]{6}\z/, value), do: value
  end

  def parse(_), do: nil
end
