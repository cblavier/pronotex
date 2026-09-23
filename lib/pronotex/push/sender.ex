defmodule Pronotex.Push.Sender do
  @moduledoc false

  def send(subscription, payload) do
    if Pronotex.Push.valid_endpoint?(subscription.endpoint) do
      body =
        WebPush.Encryption.encrypt(Jason.encode!(payload), subscription.p256dh, subscription.auth)

      # The library supplies standard encryption/signing; keep HTTP errors and
      # secret subscription endpoints out of logs, and never follow redirects.
      result =
        Req.post(subscription.endpoint,
          body: body,
          retry: false,
          redirect: false,
          receive_timeout: 5000,
          connect_options: [timeout: 5000],
          headers: [
            {"authorization", WebPush.Vapid.authorization_header(subscription.endpoint)},
            {"content-type", "application/octet-stream"},
            {"content-encoding", "aes128gcm"},
            {"ttl", "3600"},
            {"urgency", "normal"}
          ]
        )

      case result do
        {:ok, %{status: status}} when status in [200, 201, 202, 204] -> :ok
        {:ok, %{status: status}} when status in [404, 410] -> {:error, :gone}
        _ -> {:error, :unavailable}
      end
    else
      {:error, :gone}
    end
  end
end
