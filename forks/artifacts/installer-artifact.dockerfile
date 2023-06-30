#
# it is part of the build sequence of installer-artifacts metapackage for a particular architecture and operating system
#
FROM registry.ci.openshift.org/ocp/builder:rhel-8-golang-1.19-openshift-4.12 AS builder

ARG TAGS=""
ARG TARGET_OS=linux
ARG TARGET_ARCH=amd64

WORKDIR /go/src/github.com/openshift/installer

COPY . .

RUN \
    set -x ; \
    GOOS=${TARGET_OS} GOARCH=${TARGET_ARCH} DEFAULT_ARCH="$(go env GOHOSTARCH)" hack/build.sh
#
# copy result binary to blank image to avoid locat huge commit overhead and container registry fill
#
FROM scratch

COPY --from=builder /go/src/github.com/openshift/installer/bin/openshift-install /