#
# this is an installer-artifacts final metaimage, which contains all openshift-installer binaries (except baremetalm why?)
#

FROM artifacts:installer-amd64-lnx AS linuxamd64
FROM artifacts:installer-arm64-lnx AS linuxarm64
FROM artifacts:installer-amd64-mac AS macamd64
FROM artifacts:installer-arm64-mac AS macarm64

FROM registry.ci.openshift.org/ocp/4.12:installer

COPY --from=linuxamd64 /openshift-install /usr/share/openshift/linux_amd64/openshift-install
COPY --from=linuxarm64 /openshift-install /usr/share/openshift/linux_arm64/openshift-install
COPY --from=macarm64   /openshift-install /usr/share/openshift/mac_arm64/openshift-install

#								or mac_amd64?
COPY --from=macamd64   /openshift-install /usr/share/openshift/mac/openshift-install
