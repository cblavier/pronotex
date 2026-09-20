import Config

config :pronotex, :accounts, [
  %{
    id: "family",
    role: :family,
    label: "Famille",
    prefix: "PRONOTE_FAMILY",
    pin: "01234567",
    username: "test-parent",
    password: "test-password"
  },
  %{
    id: "child-1",
    role: :child,
    label: "Alice",
    prefix: "PRONOTE_CHILD_1",
    pin: "12345678",
    username: "test-child",
    password: "test-child-password"
  },
  %{
    id: "parent-1",
    role: :parent,
    label: "Camille",
    prefix: "PRONOTE_PARENT_1",
    pin: "23456789",
    username: "test-parent-1",
    password: "test-parent-password"
  }
]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :pronotex, PronotexWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "T+qW++kFZhJtjeKa6vNu5BHQuBweT+vkrr5GnpAailH6RJl4ytjuFQBVcjga8A1h",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
