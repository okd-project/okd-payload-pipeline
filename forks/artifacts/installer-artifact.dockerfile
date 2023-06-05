#
# it is part of the build sequence of installer-artifacts metapackage for a particular architecture and operating system
#
FROM registry.ci.openshift.org/ocp/builder:rhel-8-golang-1.19-openshift-4.12
ARG TAGS=""
ARG TGT_OS=linux
ARG TGT_ARCH=amd64

WORKDIR /go/src/github.com/openshift/installer
COPY . .
RUN GOOS=${TGT_OS} GOARCH=${TGT_ARCH} DEFAULT_ARCH="$(go env GOHOSTARCH)" hack/build.sh
