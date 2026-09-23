# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :pronotex, ecto_repos: [Pronotex.Repo]

config :pronotex, Pronotex.Repo,
  database: Path.expand("../data/pronotex_#{config_env()}.db", __DIR__),
  pool_size: 1,
  log: false,
  journal_mode: :wal,
  default_transaction_mode: :immediate,
  busy_timeout: 5_000

config :phoenix, :filter_parameters, ["password", "pin", "token", "secret"]

# Configure the endpoint
config :pronotex, PronotexWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PronotexWeb.ErrorHTML, json: PronotexWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Pronotex.PubSub,
  live_view: [signing_salt: "qcgcPIs4"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  pronotex: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  pronotex: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
