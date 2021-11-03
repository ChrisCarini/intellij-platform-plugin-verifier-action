# AdoptOpenJDK image with Java 11 JDK installed on an Alpine Linux base image.
# We want an Alpine Linux base image to keep the overall image size small.
# We want a Java 11 JDK image as the verifier CLI needs a JDK (as opposed to a JRE).
#
# Ref: https://hub.docker.com/_/adoptopenjdk
# Ref: https://hub.docker.com/layers/adoptopenjdk/openjdk11/alpine-slim/images/sha256-ef65f9b755ba9d70580d3b5e4ea7f133c68cecc096171959d011b38c4728f6b2?context=explore
FROM adoptopenjdk/openjdk11:alpine-slim

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