# eclipse-temurin image with Java 11 JDK installed on an Alpine Linux base image.
# We want an Alpine Linux base image to keep the overall image size small.
# We want a Java 11 JDK image as the verifier CLI needs a JDK (as opposed to a JRE).
#
# Ref: https://hub.docker.com/_/eclipse-temurin
# Ref: https://hub.docker.com/layers/library/eclipse-temurin/11-jdk-alpine/images/sha256-38cd0ba262dad90d8ba61e6dbc6328bf50043a62c5f9b4e6108d7f5f295c2ec5?context=explore
FROM eclipse-temurin:11-jdk-alpine

# We prefer bash for our script, so let's install that
RUN apk --no-cache add bash

# We need jq to find the latest version of the verifier jar
RUN apk --no-cache add jq

# We need curl to download the verifier jar
RUN apk --no-cache add curl

# We need zip to test the downloaded IDEs
RUN apk --no-cache add zip

# We may need the gh CLI to run API commands (for more GH API requests per hour)
RUN wget https://github.com/cli/cli/releases/download/v2.1.0/gh_2.1.0_linux_386.tar.gz -O ghcli.tar.gz && tar --strip-components=1 -xf ghcli.tar.gz

# Copies your code file from the repository to the filesystem path `/` of the container
COPY entrypoint.sh /entrypoint.sh

# Code file to execute when the docker container starts up (`entrypoint.sh`)
ENTRYPOINT ["/entrypoint.sh"]