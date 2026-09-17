defmodule Pronotex.Pronote.Transport do
  @moduledoc false
  alias Pronotex.Pronote.{Crypto, Error}

  @derive {Inspect, only: [:root, :order]}
  defstruct [
    :root,
    :session,
    :space,
    :request,
    :key,
    :iv,
    order: 1,
    encrypted?: false,
    compressed?: false,
    cookies: %{}
  ]

  def open(config, req_options) do
    # Disallow redirects and retries: credentials and ordered RPCs stay on this origin.
    request =
      Req.new(
        Keyword.merge(req_options,
          retry: false,
          redirect: false,
          receive_timeout: 15_000,
          connect_options: [timeout: 10_000],
          headers: [
            {"user-agent",
             "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:73.0) Gecko/20100101 Firefox/73.0"}
          ]
        )
      )

    state = %__MODULE__{
      root:
        config.url
        |> String.replace_suffix("/parent.html", "")
        |> String.replace_suffix("/eleve.html", ""),
      request: request,
      key: Crypto.md5(""),
      iv: <<0::128>>
    }

    {response, state} = http(state, method: :get, url: config.url)
    attrs = attributes(response.body)
    if attrs["a"] != config.space or not is_integer(attrs["h"]), do: raise(Error.new(:protocol))
    iv_seed = :crypto.strong_rand_bytes(16)
    uuid = if truthy?(attrs["http"]), do: Crypto.rsa_encrypt(iv_seed), else: iv_seed

    state = %{
      state
      | session: attrs["h"],
        space: attrs["a"],
        encrypted?: truthy?(attrs["CrA"]),
        compressed?: truthy?(attrs["CoA"])
    }

    {parameters, state} =
      call(
        state,
        "FonctionParametres",
        %{
          "data" => %{"Uuid" => Base.encode64(uuid)}
        },
        Crypto.md5(iv_seed)
      )

    {parameters, state}
  end

  def call(state, function, data, response_iv \\ nil) do
    number = Crypto.encrypt(Integer.to_string(state.order), state.key, state.iv) |> Crypto.hex()

    payload = %{
      "session" => state.session,
      "no" => number,
      "id" => function,
      "dataSec" => encode(data, state)
    }

    url = "#{state.root}/appelfonction/#{state.space}/#{state.session}/#{number}"
    {response, state} = http(state, method: :post, url: url, json: payload)
    state = %{state | order: state.order + 2, iv: response_iv || state.iv}
    body = if is_binary(response.body), do: Jason.decode!(response.body), else: response.body

    if error = body["Erreur"] do
      code = error["G"]

      reason =
        case code do
          n when n in [10, 22] -> :session_expired
          25 -> :rate_limited
          _ -> :server
        end

      raise Error.new(reason, code)
    end

    {decode(Map.fetch!(body, "dataSec"), state) |> Map.fetch!("data"), state}
  end

  defp http(state, options) do
    cookies = Enum.map_join(state.cookies, "; ", fn {k, v} -> "#{k}=#{v}" end)
    options = Keyword.put(options, :headers, [{"cookie", cookies}])

    case Req.request(state.request, options) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        jar =
          Enum.reduce(Req.Response.get_header(response, "set-cookie"), state.cookies, fn cookie,
                                                                                         jar ->
            [pair | attributes] = String.split(cookie, ";")

            case String.split(pair, "=", parts: 2) do
              [key, value] ->
                if Enum.any?(attributes, &(String.downcase(String.trim(&1)) == "max-age=0")),
                  do: Map.delete(jar, key),
                  else: Map.put(jar, key, value)

              _ ->
                jar
            end
          end)

        {response, %{state | cookies: jar}}

      {:ok, %{status: status}} ->
        raise Error.new(:http, status)

      {:error, _} ->
        raise Error.new(:network)
    end
  end

  defp encode(data, state) do
    encoded =
      if state.compressed?,
        do: data |> Jason.encode!() |> Crypto.hex() |> Crypto.deflate(),
        else: Jason.encode!(data)

    cond do
      state.encrypted? -> Crypto.encrypt(encoded, state.key, state.iv) |> Base.encode16()
      state.compressed? -> Base.encode16(encoded)
      true -> data
    end
  end

  defp decode(data, state) do
    data =
      if state.encrypted?, do: Crypto.decrypt(Crypto.unhex(data), state.key, state.iv), else: data

    data =
      if state.compressed? do
        bytes = if state.encrypted?, do: data, else: Crypto.unhex(data)
        Crypto.inflate(bytes)
      else
        data
      end

    if is_binary(data), do: Jason.decode!(data), else: data
  end

  defp attributes(html) when is_binary(html) do
    case Regex.run(~r/Start\s*\(\s*(\{[^}]*\})\s*\)/, html, capture: :all_but_first) do
      [json] ->
        # Older servers use quoted keys with single quotes or bare JS keys.
        json =
          json
          |> String.replace("'", "\"")
          |> then(&Regex.replace(~r/([{,]\s*)([A-Za-z]\w*)\s*:/, &1, "\\1\"\\2\":"))

        attrs = Jason.decode!(json)

        Map.new(attrs, fn {key, value} ->
          {key,
           if(key in ["h", "a"] and is_binary(value), do: String.to_integer(value), else: value)}
        end)

      _ ->
        raise Error.new(:protocol)
    end
  end

  defp truthy?(value), do: value in [true, 1, "true", "1"]
end
