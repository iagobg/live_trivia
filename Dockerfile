# syntax=docker/dockerfile:1

ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28
ARG DEBIAN_VERSION=trixie

ARG BUILDER_IMAGE=elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION}-slim
ARG RUNNER_IMAGE=debian:${DEBIAN_VERSION}-slim

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends build-essential ca-certificates git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix deps.compile
RUN mix compile
RUN mix assets.deploy
RUN mix release

FROM ${RUNNER_IMAGE} AS runner

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends ca-certificates libstdc++6 libncurses6 openssl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/sh app

WORKDIR /app

ENV HOME=/app \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    MIX_ENV=prod \
    PHX_SERVER=true \
    PORT=3070

COPY --from=builder --chown=app:app /app/_build/prod/rel/live_trivia ./

USER app

EXPOSE 3070

CMD ["/app/bin/live_trivia", "start"]
