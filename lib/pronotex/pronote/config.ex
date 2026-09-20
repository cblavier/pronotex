defmodule Pronotex.Pronote.Config do
  @moduledoc "Direct parent and student login configuration, loaded lazily from environment variables."
  alias Pronotex.Pronote.Error

  @derive {Inspect, only: [:url]}
  defstruct [:url, :username, :password, space: 2]

  def from_env, do: from_account("family")

  def from_account(id) do
    with %{role: role} <- Pronotex.Accounts.get(id) do
      {username, password} = Pronotex.Accounts.credentials(id)

      build(
        System.get_env("PRONOTE_URL", ""),
        username,
        password,
        if(role == :child, do: 3, else: 2)
      )
    else
      _ -> {:error, Error.new(:missing_credentials)}
    end
  end

  def student_from_env(child) do
    build(
      System.get_env("PRONOTE_URL", ""),
      Pronotex.Family.value(child, "USERNAME"),
      Pronotex.Family.value(child, "PASSWORD"),
      3
    )
  end

  def build(base, username, password, space) do
    uri = URI.parse(base)

    if uri.scheme == "https" and is_binary(uri.host) and uri.host != "" and
         is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment) and
         not Enum.any?(
           String.split(String.downcase(uri.path || ""), "/"),
           &String.ends_with?(&1, ".html")
         ) do
      validate(%__MODULE__{
        url:
          String.trim_trailing(base, "/") <>
            if(space == 3, do: "/eleve.html", else: "/parent.html"),
        username: username,
        password: password,
        space: space
      })
    else
      {:error, Error.new(:invalid_url)}
    end
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
