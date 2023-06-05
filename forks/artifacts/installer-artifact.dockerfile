FROM registry.ci.openshift.org/ocp/builder:rhel-8-golang-1.19-openshift-4.12 AS linuxbuilder

ARG TAGS=""
ARG TGT_OS=linux
ARG TGT_ARCH=amd64

WORKDIR /go/src/github.com/openshift/installer

COPY . .

RUN \
    go version
    GOOS=linux GOARCH=amd64 DEFAULT_ARCH="$(go env GOHOSTARCH)" hack/build.sh
#
# it is part of the build sequence of installer-artifacts metapackage for a particular architecture and operating system
#
