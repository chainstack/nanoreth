# Multi-stage build for reth-hl (nanoreth)
FROM rustlang/rust:nightly-bookworm AS builder

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    libclang-dev \
    clang \
    cmake \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy dependency files first for better layer caching
COPY Cargo.toml Cargo.lock ./

# Copy the source code structure to build dependencies
COPY src/ src/

# Build dependencies and the application
RUN cargo build --release --bin reth-hl

# Runtime stage
FROM debian:bookworm-slim AS runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user
RUN groupadd -r reth && useradd -r -g reth reth

# Create necessary directories
RUN mkdir -p /data/reth \
    && mkdir -p /data/evm-blocks \
    && mkdir -p /home/reth/.aws \
    && chown -R reth:reth /data /home/reth

# Copy the binary from builder stage
COPY --from=builder /app/target/release/reth-hl /usr/local/bin/reth-hl

# Make binary executable
RUN chmod +x /usr/local/bin/reth-hl

# Switch to non-root user
USER reth

# Set environment variables
ENV RUST_LOG=info
ENV RUST_BACKTRACE=1

# Expose ports
# 8545 - HTTP/WS RPC
# 30303 - P2P networking
# 9001 - Metrics (if enabled)
EXPOSE 8545 30303 9001

# Set working directory
WORKDIR /data

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8545 || exit 1

CMD ["reth-hl", "node", \
     "--http", "--http.addr", "0.0.0.0", "--http.port", "8545", \
     "--http.api", "eth,ots,net,web3", \
     "--ws", "--ws.addr", "0.0.0.0", "--ws.port", "8545", \
     "--ws.origins", "*", "--ws.api", "eth,ots,net,web3", \
     "--s3"]
