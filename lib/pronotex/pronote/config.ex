defmodule Pronotex.Pronote.Config do
  @moduledoc "Direct parent and student login configuration, loaded lazily from environment variables."
  alias Pronotex.Pronote.Error

  @derive {Inspect, only: [:url]}
  defstruct [:url, :username, :password, space: 2]

  def from_env do
    validate(%__MODULE__{
      url: System.get_env("PRONOTE_URL", ""),
      username: System.get_env("PRONOTE_USERNAME"),
      password: System.get_env("PRONOTE_PASSWORD")
    })
  end

  def student_from_env(child) do
    url =
      System.get_env("PRONOTE_URL", "")

    validate(%__MODULE__{
      url: String.replace_suffix(url, "/parent.html", "/eleve.html"),
      username: Pronotex.Family.value(child, "USERNAME"),
      password: Pronotex.Family.value(child, "PASSWORD"),
      space: 3
    })
  end

  def student_configured?(nil), do: false
  def student_configured?(child), do: match?({:ok, _}, student_from_env(child))

  def validate(%__MODULE__{} = config) do
    uri = URI.parse(config.url || "")

    cond do
      uri.scheme != "https" or is_nil(uri.host) or uri.host == "" or
        config.space not in [2, 3] or
        not String.ends_with?(
          uri.path || "",
          if(config.space == 3, do: "/eleve.html", else: "/parent.html")
        ) or
        not is_nil(uri.userinfo) or not is_nil(uri.query) or not is_nil(uri.fragment) ->
        {:error, Error.new(:invalid_url)}

      config.username in [nil, ""] or config.password in [nil, ""] ->
        {:error, Error.new(:missing_credentials)}

      true ->
        {:ok, config}
    end
  end
end
