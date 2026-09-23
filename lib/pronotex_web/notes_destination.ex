defmodule PronotexWeb.NotesDestination do
  @moduledoc false

  # Only accept a child's Notes route, never an arbitrary post-login redirect.
  def validate(value) when is_binary(value) and byte_size(value) <= 512 do
    with %URI{scheme: nil, host: nil, fragment: nil, path: path, query: query} <- URI.parse(value),
         [_, child] <- Regex.run(~r"\A/([\p{L}\p{N}_-]+)/notes\z"u, URI.decode(path || "")) do
      params = URI.decode_query(query || "")
      period = params["period"]
      base = "/" <> URI.encode(child, &URI.char_unreserved?/1) <> "/notes"

      if is_binary(period) and Regex.match?(~r/\A[a-z0-9-]{1,80}\z/, period),
        do: base <> "?" <> URI.encode_query(%{"period" => period}),
        else: base
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  def validate(_), do: nil

  def login_url(destination) do
    case validate(destination) do
      nil -> "/login"
      path -> "/login?" <> URI.encode_query(%{"return_to" => path})
    end
  end
end
