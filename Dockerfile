# Stage 1: Build pg_parquet
FROM rust:1.72 AS builder

# Install dependencies for building pg_parquet
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libssl-dev \
    pkg-config \
    git \
    ca-certificates \
    postgresql-server-dev-all

# Install cargo-pgrx at version matching pg_parquet's pgrx dependency
RUN cargo install cargo-pgrx --version 0.12.6 --locked

# Initialize pgrx for PostgreSQL 17
RUN cargo pgrx init --pg17 $(which pg_config)

# Clone pg_parquet repository
RUN git clone --branch v0.12.6 https://github.com/CrunchyData/pg_parquet.git /pg_parquet

# Build pg_parquet
WORKDIR /pg_parquet
RUN cargo pgrx build --release

# Stage 2: Final image
FROM postgres:17

# Install OpenSSL and sudo
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssl \
    sudo \
    ca-certificates

# Allow the postgres user to execute certain commands as root without a password
RUN echo "postgres ALL=(root) NOPASSWD: /usr/bin/mkdir, /bin/chown, /usr/bin/openssl" > /etc/sudoers.d/postgres

# Install PostGIS
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-17-postgis-3 \
    postgresql-17-postgis-3-scripts

# Copy pg_parquet extension files from the builder stage
COPY --from=builder /pg_parquet/target/release/pg_parquet.so /usr/lib/postgresql/17/lib/
COPY --from=builder /pg_parquet/target/release/pg_parquet.control /usr/share/postgresql/17/extension/
COPY --from=builder /pg_parquet/target/release/sql/pg_parquet-*.sql /usr/share/postgresql/17/extension/

# Set shared_preload_libraries via environment variable
ENV POSTGRES_SHARED_PRELOAD_LIBRARIES pg_parquet

# Add init scripts while setting permissions
COPY --chmod=755 init-ssl.sh /docker-entrypoint-initdb.d/
COPY --chmod=755 wrapper.sh /usr/local/bin/

ENTRYPOINT ["wrapper.sh"]
CMD ["postgres", "--port=5432"]
