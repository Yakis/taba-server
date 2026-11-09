# M1 local Linux verification image. Static SDK production packaging belongs to deployment step 6.
FROM swift:6.2-noble AS build
WORKDIR /build
COPY Package.swift Package.resolved ./
RUN --mount=type=cache,id=taba-swift-build,target=/build/.build swift package resolve
COPY . .
RUN --mount=type=cache,id=taba-swift-build,target=/build/.build \
    swift build -c release --product taba-server --jobs 4 \
    && mkdir -p /artifacts \
    && cp .build/release/taba-server /artifacts/ \
    && cp -R .build/release/TABA_PipelineKit.resources /artifacts/

FROM swift:6.2-noble AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends tzdata ca-certificates \
    && apt-get clean
WORKDIR /app
COPY --from=build /artifacts/taba-server /app/taba-server
COPY --from=build /artifacts/TABA_PipelineKit.resources /app/TABA_PipelineKit.resources
USER 65532:65532
ENV HOST=0.0.0.0 PORT=8090
EXPOSE 8090
ENTRYPOINT ["/app/taba-server"]
