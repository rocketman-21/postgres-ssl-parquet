FROM postgres:17

# Install OpenSSL and sudo
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssl \
    sudo \
    ca-certificates \
    wget \
    gnupg \
    lsb-release

# Allow the postgres user to execute certain commands as root without a password
RUN echo "postgres ALL=(root) NOPASSWD: /usr/bin/mkdir, /bin/chown, /usr/bin/openssl" > /etc/sudoers.d/postgres

# Add PostgreSQL APT Repository
RUN echo "deb http://apt.postgresql.org/pub/repos/apt $(grep -Po '(?<=^VERSION_CODENAME=)[^\n]*' /etc/os-release)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

# Set environment variables
ENV POSTGIS_MAJOR 3

# Install PostGIS without version pinning
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       postgresql-$PG_MAJOR-postgis-$POSTGIS_MAJOR \
       postgresql-$PG_MAJOR-postgis-$POSTGIS_MAJOR-scripts

# Install dependencies for pg_parquet
RUN apt-get install -y --no-install-recommends \
       build-essential \
       libssl-dev \
       pkg-config \
       curl \
       git \
       postgresql-server-dev-$PG_MAJOR

# Install Rust
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install cargo-pgrx at version matching pg_parquet's pgrx dependency
RUN cargo install cargo-pgrx --version 0.12.6 --locked

# Initialize pgrx for PostgreSQL 17
RUN cargo pgrx init --pg17 /usr/lib/postgresql/17/bin/pg_config

# Clone pg_parquet repository
RUN git clone https://github.com/CrunchyData/pg_parquet.git /pg_parquet

# Build and install pg_parquet
WORKDIR /pg_parquet
RUN cargo pgrx install --release

# Clean up
RUN apt-get remove -y build-essential libssl-dev pkg-config curl git \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* /pg_parquet

# Add init scripts while setting permissions
COPY --chmod=755 init-ssl.sh /docker-entrypoint-initdb.d/init-ssl.sh
COPY --chmod=755 wrapper.sh /usr/local/bin/wrapper.sh

# Set shared_preload_libraries via environment variable
ENV POSTGRES_SHARED_PRELOAD_LIBRARIES pg_parquet

ENTRYPOINT ["wrapper.sh"]
CMD ["postgres", "--port=5432"]
