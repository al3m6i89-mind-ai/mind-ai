FROM golang:1.23-bookworm AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 go build -trimpath -o /agent .

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends adb ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
# scrcpy-server (Apache-2.0) runs inside each phone to capture the screen and inject input.
RUN curl -fsSL -o /opt/scrcpy-server https://github.com/Genymobile/scrcpy/releases/download/v2.7/scrcpy-server-v2.7 \
    && echo "a23c5659f36c260f105c022d27bcb3eafffa26070e7baa9eda66d01377a1adba  /opt/scrcpy-server" | sha256sum -c - \
    && mkdir -p /opt/nuvola && mv /opt/scrcpy-server /opt/nuvola/scrcpy-server
COPY --from=docker:27-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=build /agent /usr/local/bin/nuvola-agent
ENTRYPOINT ["/usr/local/bin/nuvola-agent"]
