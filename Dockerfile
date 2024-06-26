ARG TARGETARCH=ARGUMENT_NOT_FILLED_IN
FROM ubuntu:latest
LABEL org.opencontainers.image.source="https://github.com/josxha/zulu-openjdk-docker" \
      org.opencontainers.image.authors="https://github.com/josxha" \
      org.opencontainers.image.url="https://hub.docker.com/r/josxha/zulu-openjdk" \
      org.opencontainers.image.documentation="https://github.com/josxha/zulu-openjdk-docker/blob/main/README.md" \
      org.opencontainers.image.title="Zulu OpenJDK" \
      org.opencontainers.image.description="Automatic Docker builds for Zulu OpenJDK"

COPY openjdk-${TARGETARCH}.tar.gz openjdk.tar.gz

# install OpenJDK
RUN tar -xzvf openjdk.tar.gz && \
    rm openjdk.tar.gz && \
    mv zulu* /java

ENV PATH="/java/bin:${PATH}"
WORKDIR /java