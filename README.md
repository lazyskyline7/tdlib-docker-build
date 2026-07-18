# TDLib Docker Image

![TDLib Version](https://img.shields.io/badge/TDLib-1.8.66-blue)
[![Docker Pulls](https://img.shields.io/docker/pulls/lazyskyline/tdlib)](https://hub.docker.com/r/lazyskyline/tdlib)
[![Image Size](https://img.shields.io/docker/image-size/lazyskyline/tdlib/latest)](https://hub.docker.com/r/lazyskyline/tdlib)
[![Deployment](https://github.com/klhq/tdlib-docker/actions/workflows/build-and-push.yml/badge.svg)](https://github.com/klhq/tdlib-docker/actions/workflows/build-and-push.yml)

Prebuilt, multi-arch Docker images of [TDLib (Telegram Database Library)](https://core.telegram.org/tdlib). Drop `libtdjson.so` into your bot, client, or service and skip the 30–60 minute TDLib compile.

```sh
docker pull lazyskyline/tdlib        # Debian, glibc — default
docker pull lazyskyline/tdlib:alpine # Alpine, musl — opt-in
```

Both variants ship `linux/amd64` and `linux/arm64`.

---

## Which tag should I pull?

| Your stack | Pull this |
|---|---|
| Python (`python:3.x`, `python:3.x-slim`), Node (`node:x`, `node:x-slim`), Go (cgo), Java/Kotlin (JNI), bare-metal Ubuntu/Debian/RHEL/Arch | **`lazyskyline/tdlib`** (Debian, glibc) |
| Everything on Alpine (`python:3.x-alpine`, `node:x-alpine`, static Go on musl) | `lazyskyline/tdlib:alpine` |
| Specific TDLib version | `lazyskyline/tdlib:1.8.64` (Debian) or `lazyskyline/tdlib:1.8.64-alpine` |

> **Compatibility rule:** a shared library built against one libc cannot be loaded by a process running on the other. Pick the variant matching your consumer's libc — **don't mix glibc and musl** in the same image.

If unsure, pull the default (`lazyskyline/tdlib`). It works for ~95% of real-world TDLib consumers.

---

## Quick start

Three patterns, in order of how often they're used.

### Pattern A — `COPY --from` into your own image (recommended)

The canonical pattern. Your runtime image stays small; you just lift `libtdjson.so`.

> **Use a directory COPY (`/usr/local/lib/`), not a wildcard.** Docker's `COPY` de-references symlinks when the source is a glob or a single symlink file, which turns the unversioned `libtdjson.so` link into a duplicate 33 MB regular file and breaks `dlopen("libtdjson.so")` on glibc. Copying the directory preserves the symlink and keeps the image small.

**Python:**

```dockerfile
FROM lazyskyline/tdlib:latest AS tdlib

FROM python:3.12-slim
COPY --from=tdlib /usr/local/lib/ /usr/local/lib/
RUN ldconfig
RUN pip install --no-cache-dir python-telegram
COPY app.py /app/
WORKDIR /app
CMD ["python", "app.py"]
```

**Node.js:**

```dockerfile
FROM lazyskyline/tdlib:latest AS tdlib

FROM node:20-slim
COPY --from=tdlib /usr/local/lib/ /usr/local/lib/
RUN ldconfig
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
CMD ["node", "bot.js"]
```

**Go (cgo bindings):**

```dockerfile
FROM lazyskyline/tdlib:latest AS tdlib

FROM golang:1.22-bookworm
COPY --from=tdlib /usr/local/lib/ /usr/local/lib/
RUN ldconfig
WORKDIR /src
COPY . .
RUN go build -o /bot ./cmd/bot
CMD ["/bot"]
```

**Python (Alpine consumer — `:alpine` variant):**

The Alpine image is built with clang/libc++, so Alpine consumers must install those runtime libraries explicitly.

```dockerfile
FROM lazyskyline/tdlib:alpine AS tdlib

FROM python:3.12-alpine
RUN apk add --no-cache libssl3 zlib libc++ libgcc llvm-libunwind
COPY --from=tdlib /usr/local/lib/ /usr/local/lib/
RUN pip install --no-cache-dir python-telegram
COPY app.py /app/
WORKDIR /app
CMD ["python", "app.py"]
```

### Pattern B — `FROM lazyskyline/tdlib` as a base

Simpler when your app is mostly TDLib glue. You inherit Debian + the lib in one shot.

```dockerfile
FROM lazyskyline/tdlib:latest
USER root
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-pip \
 && rm -rf /var/lib/apt/lists/*
USER app
COPY app.py /app/
CMD ["python3", "/app/app.py"]
```

### Pattern C — Extract `libtdjson.so` for bare-metal / CI use

Pull the lib out of the image and drop it next to a binary running on a VM, CI runner, or developer laptop.

```sh
docker create --name td-extract lazyskyline/tdlib:latest
docker cp td-extract:/usr/local/lib/. ./tdlib-libs/   # trailing /. copies directory contents and preserves symlinks
docker rm td-extract
sudo cp -P ./tdlib-libs/* /usr/local/lib/ && sudo ldconfig
```

The trailing `/.` matters: `docker cp` follows a symlink if you point it at one directly, but copies the symlink-as-symlink when you copy a directory's contents. After installing to `/usr/local/lib`, `cp -P` preserves the symlink, and `ldconfig` registers both `libtdjson.so` and the versioned SONAME in the loader cache.

The extracted `.so` is a standard glibc shared library — usable on any modern glibc Linux (Ubuntu 22.04+, Debian 12+, RHEL/Rocky 9+, Arch, Fedora). For Alpine hosts, extract from `:alpine` instead.

---

## Compatibility matrix

| TDLib variant | Consumer image / host | Works? |
|---|---|---|
| `lazyskyline/tdlib` (Debian, glibc) | `python:3.x` / `python:3.x-slim` | ✅ |
| `lazyskyline/tdlib` (Debian, glibc) | `node:x` / `node:x-slim` | ✅ |
| `lazyskyline/tdlib` (Debian, glibc) | `golang:1.x-bookworm` | ✅ |
| `lazyskyline/tdlib` (Debian, glibc) | `openjdk:x` / `eclipse-temurin:x` | ✅ |
| `lazyskyline/tdlib` (Debian, glibc) | Ubuntu 22.04+ / Debian 12+ / RHEL 9+ host | ✅ |
| `lazyskyline/tdlib` (Debian, glibc) | `*-alpine` consumer | ❌ |
| `lazyskyline/tdlib:alpine` (musl) | `*-alpine` consumer | ✅ |
| `lazyskyline/tdlib:alpine` (musl) | glibc consumer (slim, bookworm, ubuntu, etc.) | ❌ |

glibc is forward-compatible: the Debian variant (built on bookworm, glibc 2.36) runs anywhere with glibc ≥ 2.36. For older systems (Ubuntu 20.04, RHEL 8), build the image locally on `debian:bullseye` — see [Building locally](#building-locally).

---

## What's inside the image

| | Debian variant | Alpine variant |
|---|---|---|
| **Base** | `debian:bookworm-slim` | `alpine:3.21` |
| **libc** | glibc 2.36 | musl 1.2.5 |
| **C++ runtime** | libstdc++ (gcc) | libc++ (clang) |
| **Library** | `/usr/local/lib/libtdjson.so` | same |
| **User** | non-root `app` | same |
| **Headers / static libs** | stripped (consumers use dlopen + the JSON ABI) | same |
| **Approx compressed size** | ~30 MB | ~26 MB |

Both variants link OpenSSL 3 and zlib dynamically. Debug symbols are stripped.

---

## All tags

| Tag | Variant | Architectures |
|---|---|---|
| `latest` | Debian | amd64 + arm64 |
| `1.8.64` | Debian | amd64 + arm64 |
| `1.8.64-debian` | Debian (explicit alias) | amd64 + arm64 |
| `debian` | Debian (latest version) | amd64 + arm64 |
| `alpine` | Alpine (latest version) | amd64 + arm64 |
| `1.8.64-alpine` | Alpine | amd64 + arm64 |

Full list: [hub.docker.com/r/lazyskyline/tdlib/tags](https://hub.docker.com/r/lazyskyline/tdlib/tags).

---

## Building locally

```sh
# Debian variant (default)
docker buildx build -f Dockerfile -t tdlib-local .

# Alpine variant
docker buildx build -f Dockerfile.alpine -t tdlib-local-alpine .

# Multi-arch (requires QEMU + buildx setup)
docker buildx build --platform linux/amd64,linux/arm64 -f Dockerfile -t tdlib-local .
```

To target an older glibc, swap the base images in `Dockerfile` from `bookworm` to `bullseye` (glibc 2.31, covers Ubuntu 20.04).

---

## Versioning

The image version tracks TDLib upstream's version, sourced from [`CMakeLists.txt`](./CMakeLists.txt) (`project(TDLib VERSION X.Y.Z ...)`). Releases are tagged on GitHub when upstream cuts a new version; CI then builds and pushes the matching Docker tags.

See [GitHub Releases](https://github.com/klhq/tdlib-docker/releases) for per-version changelogs.

---

## Breaking change: default variant is now Debian

`lazyskyline/tdlib:latest` previously pointed to the Alpine-based (musl) image. It now points to the Debian-based (glibc) variant, which matches the libc of the overwhelming majority of TDLib consumers (Python, Node, Go cgo, Java, Ubuntu/Debian/RHEL hosts).

**If you were relying on the Alpine variant**, pin to `lazyskyline/tdlib:alpine` for the moving Alpine tag, or `lazyskyline/tdlib:<version>-alpine` for a versioned pin.

---

## Resources

- [TDLib documentation](https://core.telegram.org/tdlib)
- [TDLib API reference](https://core.telegram.org/tdlib/docs/)
- [TDLib examples (upstream)](https://github.com/tdlib/td/tree/master/example)
- [This repository's source & issues](https://github.com/klhq/tdlib-docker)

## License

TDLib is licensed under the [Boost Software License 1.0](http://www.boost.org/LICENSE_1_0.txt). The Docker packaging in this repository is provided under the same license.
