# Build stage
FROM debian:bookworm AS builder

# Install build dependencies. gcc + libstdc++ is TDLib upstream's primary
# target, so we get their CI's bug fixes for free.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake gperf zlib1g-dev libssl-dev php git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Copy the source code
COPY . /td

# Set the working directory
WORKDIR /td/build

# Configure and build the project. Cache build tool state for faster rebuilds.
RUN --mount=type=cache,target=/root/.cache \
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX:PATH=/usr/local ..
RUN --mount=type=cache,target=/root/.cache \
    cmake --build . --parallel $(nproc) --target install

# Strip debug symbols and remove static libs, headers, cmake files
RUN find /usr/local/lib -type f -name '*.so*' -exec strip --strip-unneeded {} + && \
    find /usr/local/lib -type f -name '*.a' -delete && \
    rm -rf /usr/local/include /usr/local/lib/cmake

# Final stage
FROM debian:bookworm-slim

# Install only runtime dependencies (glibc + libstdc++ come with the base)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 zlib1g \
 && rm -rf /var/lib/apt/lists/*

# Create a non-root user for runtime
RUN groupadd -r app && useradd -r -g app app

# Copy only the shared library from the builder stage
COPY --from=builder --chown=app:app /usr/local/lib/libtdjson.so* /usr/local/lib/

# COPY de-references the linker-name symlink into a duplicate regular file
# (~33 MB wasted). Restore it as a real symlink so `dlopen("libtdjson.so")` —
# what TDLib's Python example and many ctypes-based bindings use — resolves
# via the ldconfig cache, not just the versioned SONAME.
RUN cd /usr/local/lib && \
    real=$(ls libtdjson.so.* | sort -V | tail -n1) && \
    rm -f libtdjson.so && ln -s "$real" libtdjson.so && \
    chown -h app:app libtdjson.so && \
    ldconfig

# Ensure /usr/local/bin is in PATH and run as non-root
ENV PATH="/usr/local/bin:${PATH}"
USER app
