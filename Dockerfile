# OpenJDK image with Java 1.8 JDK installed on an Alpine Linux base image.
# We want an Alpine Linux base image to keep the overall image size small.
# We want a Java 1.8 JDK image as the verifier CLI needs a JDK (as opposed to a JRE).
#
# Ref: https://hub.docker.com/_/openjdk
# Ref: https://hub.docker.com/layers/openjdk/library/openjdk/8-jdk-alpine/images/sha256-210ecd2595991799526a62a7099718b149e3bbefdb49764cc2a450048e0dd4c0?context=explore
FROM openjdk:8-jdk-alpine

# We prefer bash for our script, so let's install that
RUN apk --no-cache add bash

# We need jq to find the latest version of the verifier jar
RUN apk --no-cache add jq

# We need curl to download the verifier jar
RUN apk --no-cache add curl

# Copies your code file from the repository to the filesystem path `/` of the container
COPY entrypoint.sh /entrypoint.sh

# Code file to execute when the docker container starts up (`entrypoint.sh`)
ENTRYPOINT ["/entrypoint.sh"]