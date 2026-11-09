# Deployment image: a fully static Linux binary (Swift Static Linux SDK, musl) on a small Alpine base
# with tzdata and ca-certificates. The build stage runs on the builder's own architecture and
# cross-compiles to the target's, so `docker buildx build --platform linux/amd64` on an arm64 Mac
# needs no emulation. The Static SDK version must match the compiler exactly.
ARG SWIFT_VERSION=6.2.4
ARG STATIC_SDK_VERSION=0.1.0
ARG STATIC_SDK_CHECKSUM=24bdf84495dd31a6de2eb679647c1982b747bfbfe1a2060c779d84dcecd902a4

FROM --platform=$BUILDPLATFORM swift:${SWIFT_VERSION}-noble AS build
ARG SWIFT_VERSION
ARG STATIC_SDK_VERSION
ARG STATIC_SDK_CHECKSUM
ARG TARGETARCH
RUN swift sdk install \
    "https://download.swift.org/swift-${SWIFT_VERSION}-release/static-sdk/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE_static-linux-${STATIC_SDK_VERSION}.artifactbundle.tar.gz" \
    --checksum "${STATIC_SDK_CHECKSUM}"
WORKDIR /build
COPY Package.swift Package.resolved ./
COPY GuideKit/Package.swift GuideKit/Package.swift
RUN --mount=type=cache,id=taba-swift-static-build,target=/build/.build swift package resolve
COPY . .
RUN --mount=type=cache,id=taba-swift-static-build,target=/build/.build \
    case "$TARGETARCH" in \
      amd64) triple=x86_64-swift-linux-musl ;; \
      arm64) triple=aarch64-swift-linux-musl ;; \
      *) echo "unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac \
    && swift build -c release --swift-sdk "$triple" --product taba-server --jobs 4 \
    && bin="$(swift build -c release --swift-sdk "$triple" --show-bin-path)" \
    && mkdir -p /artifacts \
    && cp "$bin/taba-server" /artifacts/ \
    && cp -R "$bin/TABA_PipelineKit.resources" /artifacts/

FROM alpine:3.22 AS runtime
RUN apk add --no-cache tzdata ca-certificates
WORKDIR /app
COPY --from=build /artifacts/taba-server /app/taba-server
COPY --from=build /artifacts/TABA_PipelineKit.resources /app/TABA_PipelineKit.resources
USER 65532:65532
ENV HOST=0.0.0.0 PORT=8090
EXPOSE 8090
# BusyBox wget is part of the Alpine base, so the health check needs no extra package.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8090/health || exit 1
ENTRYPOINT ["/app/taba-server"]
