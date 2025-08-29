# Build stage
FROM debian:bookworm AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        make git zlib1g-dev libssl-dev gperf php-cli cmake clang libc++-dev libc++abi-dev && \
    rm -rf /var/lib/apt/lists/*

# Copy the source code
COPY . /td

# Set the working directory
WORKDIR /td/build

# Set environment variables for clang
ENV CXXFLAGS="-stdlib=libc++"
ENV CC=/usr/bin/clang
ENV CXX=/usr/bin/clang++

# Configure and build the project
RUN cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX:PATH=/usr/local ..
RUN cmake --build . --target install

# Final stage
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install only runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libssl3 zlib1g libc++1 && \
    ldconfig && \
    rm -rf /var/lib/apt/lists/*

# Copy the built libraries/binaries from the builder stage
COPY --from=builder /usr/local /usr/local

# Ensure /usr/local/bin is in PATH
ENV PATH="/usr/local/bin:${PATH}"