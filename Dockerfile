# Multi-stage server image (issue #51): the builder fetches the same
# Godot 4.7-stable linux x86_64 binary family the CI snapshot uses and
# pre-imports the project; the runtime ships only that binary + project
# on Debian slim. Packaging only — the server contract is unchanged.
ARG GODOT_VERSION=4.7.2-stable

FROM debian:bookworm-slim AS builder
ARG GODOT_VERSION
RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl unzip \
	&& rm -rf /var/lib/apt/lists/*
RUN curl -fL -o /tmp/godot.zip \
		"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
	&& unzip -o /tmp/godot.zip -d /tmp/godot \
	&& install -m 0755 "/tmp/godot/Godot_v${GODOT_VERSION}_linux.x86_64" /usr/local/bin/godot \
	&& rm -rf /tmp/godot.zip /tmp/godot \
	&& godot --version
WORKDIR /app
COPY . /app
RUN godot --headless --path /app --import

FROM debian:bookworm-slim
RUN useradd --create-home --user-group together \
	&& mkdir -p /data && chown together:together /data
COPY --from=builder /usr/local/bin/godot /usr/local/bin/godot
COPY --from=builder /app /app
WORKDIR /app
USER together
EXPOSE 8080
CMD ["godot", "--headless", "--path", "/app", "--", "--serve", "--port", "8080"]
