# Dockerfile for building and testing pg_ttl_index extension
FROM postgres:15

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    postgresql-server-dev-15 \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy extension source
WORKDIR /pg_ttl_index
COPY . .

# Build and install the extension
RUN make clean && make && make install

# Copy custom PostgreSQL configuration
RUN echo "shared_preload_libraries = 'pg_ttl_index'" >> /usr/share/postgresql/postgresql.conf.sample
RUN echo "pg_ttl_index.naptime = 10" >> /usr/share/postgresql/postgresql.conf.sample
RUN echo "log_min_messages = debug1" >> /usr/share/postgresql/postgresql.conf.sample

# Create initialization script
COPY test/docker-test.sql /docker-entrypoint-initdb.d/01-test.sql

# Expose PostgreSQL port
EXPOSE 5432
