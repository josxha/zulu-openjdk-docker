# Template Dockerfile, update_docker_images.dart replaces {{variable_name}} with its values
# Using buildx buildkit for multi arch images

FROM alpine:latest

LABEL org.opencontainers.image.source="https://github.com/josxha/zulu-openjdk-docker" \
      org.opencontainers.image.authors="https://github.com/josxha" \
      org.opencontainers.image.url="https://hub.docker.com/r/josxha/zulu-openjdk" \
      org.opencontainers.image.documentation="https://github.com/josxha/zulu-openjdk-docker/blob/main/README.md" \
      org.opencontainers.image.title="Zulu OpenJDK" \
      org.opencontainers.image.description="Automatic Docker builds for Paper Minecraft"

# TODO install zulu openjdk
RUN test $TARGETARCH -eq "x86" && wget {{download_url_x86}} -o openjdk-x86.{{extension_x86}}
RUN test $TARGETARCH -eq "arm" && wget {{download_url_arm}} -o openjdk-arm.{{extension_arm}}

ENTRYPOINT ["java", "-version"]