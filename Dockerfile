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

# ARG needed for buildkit
ARG TARGETARCH
COPY openjdk-${TARGETARCH}.tar.gz openjdk.tar.gz

# install OpenJDK
RUN tar -xzvf openjdk.tar.gz
RUN export PATH=/java/bin:$PATH

ENTRYPOINT ["java", "-version"]