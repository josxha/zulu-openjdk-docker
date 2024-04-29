# Automatic Docker builds for Zulu OpenJDK

### This Project is currently under development. Do not use!

This repository checks automatically every day for new Zulu OpenJDK releases, builds new images with them and uploads them to the docker registry.

It's meant to be a open alternative to Microsoft's builds for Azure and more advanced builds than Azul's docker images of Zulu OpenJDK. 

## Links
- Repository: [github.com/josxha/zulu-openjdk-docker](https://github.com/josxha/zulu-openjdk-docker)
- Azul Zulu: [www.azul.com](https://www.azul.com/)
- Supported Platforms: [docs.azul.com/core/zulu-openjdk/supported-platforms](https://docs.azul.com/core/zulu-openjdk/supported-platforms)
- Official builds from Azul (no arm64 support): [hub.docker.com/r/azul/zulu-openjdk-alpine](https://hub.docker.com/r/azul/zulu-openjdk-alpine)

## Why to use this image
- [x] Builds support amd64 and arm64
- [x] Up to date with the latest OpenJDK releases
- [x] Smallest image size possible
- [x] Open source repository
- [x] No restrictive licensing

## Usage
- Run with: `docker run -it --rm josxha/zulu-openjdk:jre-21 java -version`.
- Use as a base image in your container with:
```Dockerfile
FROM josxha/zulu-openjdk:jre-21
WORKDIR /app
COPY app.jar /app/app.jar
ENTRYPOINT ["java -jar app.jar"]
```
## Tag examples
- **latest**: latest OpenJDK jre version
- **jdk**, **jre**: latest OpenJDK version
- e.g. **jre-17**, **jdk-17**: latest version of the specified OpenJDK version
- e.g. **jre-17-17.30.15** to use a specific zulu release

See all the available tag [here](https://hub.docker.com/r/josxha/zulu-openjdk/tags).