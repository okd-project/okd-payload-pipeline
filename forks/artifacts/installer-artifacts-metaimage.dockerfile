#
# this is an installer-artifacts final metaimage, which contains all openshift-installer binaries (except baremetalm why?)
#

FROM installer-artifacts:amd64-lnx AS linuxbuilder
FROM installer-artifacts:arm64-lnx AS linuxarmbuilder
FROM installer-artifacts:amd64-mac AS macbuilder
FROM installer-artifacts:arm64-mac AS macarmbuilder

FROM registry.ci.openshift.org/ocp/4.12:installer

COPY --from=linuxarmbuilder /go/src/github.com/openshift/installer/bin/openshift-install /usr/share/openshift/linux_arm64/openshift-install
COPY --from=linuxbuilder    /go/src/github.com/openshift/installer/bin/openshift-install /usr/share/openshift/linux_amd64/openshift-install
COPY --from=macarmbuilder   /go/src/github.com/openshift/installer/bin/openshift-install /usr/share/openshift/mac_arm64/openshift-install
COPY --from=macbuilder      /go/src/github.com/openshift/installer/bin/openshift-install /usr/share/openshift/mac/openshift-install
