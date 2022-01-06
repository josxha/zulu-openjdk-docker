# Template Dockerfile, update_docker_images.dart replaces {{variable_name}} with its values
# Using buildx buildkit for multi arch images

FROM alpine:latest

LABEL org.opencontainers.image.source="https://github.com/josxha/zulu-openjdk-docker" \
      org.opencontainers.image.authors="https://github.com/josxha" \
      org.opencontainers.image.url="https://hub.docker.com/r/josxha/zulu-openjdk" \
      org.opencontainers.image.documentation="https://github.com/josxha/zulu-openjdk-docker/blob/main/README.md" \
      org.opencontainers.image.title="Zulu OpenJDK" \
      org.opencontainers.image.description="Automatic Docker builds for Paper Minecraft"

RUN mkdir /java
WORKDIR /java
# download openjdk
# https://stackoverflow.com/a/58222507
RUN apkArch="$(apk --print-arch)"; \
    case "$apkArch" in \
        aarch64) wget -U "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.45 Safari/537.36" {{download_url_arm}} ;; \
        x86_64) wget -U "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.45 Safari/537.36" {{download_url_x86}} ;; \
    esac;
# install
RUN tar -xzvf openjdk.{{extension_x86}}
RUN export PATH=/java/bin:$PATH


ENTRYPOINT ["java", "-version"]