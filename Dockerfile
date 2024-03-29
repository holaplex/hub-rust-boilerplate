FROM rust:1.71.0-bullseye as chef
RUN cargo install cargo-chef --locked

WORKDIR /app

FROM chef AS planner
COPY Cargo.* ./
COPY migration migration
COPY entity entity
COPY core core
COPY api api
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder
COPY --from=planner /app/recipe.json recipe.json
# Build dependencies - this is the caching Docker layer!
RUN cargo chef cook --release --recipe-path recipe.json
# Build application
COPY Cargo.* ./
COPY migration migration
COPY entity entity
COPY core core
COPY api api

FROM builder AS builder-boilerplate-api
RUN cargo build --release --bin holaplex-rust-boilerplate-api

FROM builder AS builder-migration
RUN cargo build --release --bin migration


FROM debian:bullseye-slim as base
WORKDIR /app
RUN apt-get update -y && \
  apt-get install -y \
    ca-certificates \
    libpq5 \
    libssl1.1 \
  && \
  rm -rf /var/lib/apt/lists/*

FROM base AS boilerplate-api
ENV TZ=Etc/UTC
ENV APP_USER=runner

RUN groupadd $APP_USER \
    && useradd --uid 10000 -g $APP_USER $APP_USER \
    && mkdir -p bin

RUN chown -R $APP_USER:$APP_USER bin

USER 10000
COPY --from=builder-boilerplate-api /app/target/release/holaplex-rust-boilerplate-api bin
CMD ["bin/holaplex-rust-boilerplate-api"]

FROM base AS migrator
COPY --from=builder-migration /app/target/release/migration bin/
CMD ["bin/migration"]
