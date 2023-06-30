#
# this is an installer-artifacts final metaimage, which contains all openshift-installer binaries (except baremetal, is it needed to add here?)
#

FROM registry.ci.openshift.org/ocp/4.12:installer

COPY --from=artifacts:installer-amd64-lnx /openshift-install /usr/share/openshift/linux_amd64/openshift-install
COPY --from=artifacts:installer-arm64-lnx /openshift-install /usr/share/openshift/linux_arm64/openshift-install
COPY --from=artifacts:installer-amd64-mac /openshift-install /usr/share/openshift/mac_arm64/openshift-install

#								or mac_amd64?
COPY --from=artifacts:installer-arm64-mac /openshift-install /usr/share/openshift/mac/openshift-install
