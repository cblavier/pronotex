ARG ELIXIR_IMAGE=elixir:1.19.4-otp-28-slim
FROM ${ELIXIR_IMAGE} AS builder

RUN apt-get update && apt-get install -y --no-install-recommends build-essential git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
# Work around Erlang JIT memory mappings under amd64 emulation on Apple Silicon.
# Build-only: the native amd64 runtime on the NAS keeps the default JIT settings.
ENV MIX_ENV=prod ERL_FLAGS="+JMsingle true"
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile && mix assets.setup
COPY lib lib
COPY priv priv
COPY assets assets
RUN mix compile && mix assets.deploy
COPY config/runtime.exs config/runtime.exs
RUN mix release

# Same base guarantees compatibility with the Erlang runtime in the release.
FROM ${ELIXIR_IMAGE} AS runner
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates tzdata curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder --chown=nobody:nogroup /app/_build/prod/rel/pronotex ./
RUN mkdir -p /app/data && chown nobody:nogroup /app/data && chmod 700 /app/data
ENV LANG=C.UTF-8 MIX_ENV=prod PHX_SERVER=true PORT=4000 TZ=Europe/Paris
USER nobody
EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl --fail --silent --output /dev/null "http://127.0.0.1:${PORT}/" || exit 1
CMD ["/app/bin/pronotex", "start"]
