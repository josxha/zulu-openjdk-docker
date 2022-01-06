# Template Dockerfile, update_docker_images.dart replaces {{variable_name}} with its values
# Using buildx buildkit for multi arch images

FROM alpine:latest AS base
LABEL org.opencontainers.image.source="https://github.com/josxha/zulu-openjdk-docker" \
      org.opencontainers.image.authors="https://github.com/josxha" \
      org.opencontainers.image.url="https://hub.docker.com/r/josxha/zulu-openjdk" \
      org.opencontainers.image.documentation="https://github.com/josxha/zulu-openjdk-docker/blob/main/README.md" \
      org.opencontainers.image.title="Zulu OpenJDK" \
      org.opencontainers.image.description="Automatic Docker builds for Zulu OpenJDK"
RUN mkdir /java
WORKDIR /java

FROM base AS branch-x86_64
COPY {{name_x86}} openjdk.tar.gz

FROM base AS branch-aarch64
COPY {{name_arm}} openjdk.tar.gz

RUN arch="$(apk --print-arch)"

FROM branch-${arch} AS final
# install OpenJDK
RUN tar -xzvf openjdk.tar.gz
RUN export PATH=/java/bin:$PATH


ENTRYPOINT ["java", "-version"]