FROM release:artifacts as artifacts
FROM release:machine-config-operator as mcd

FROM fedora:37
ARG CRIO_VERSION=1.25

WORKDIR /rpms

COPY --from=artifacts /srv/repo/* /tmp/rpms
COPY manifests /

# TODO: check: is it really needed
COPY --from=mcd /usr/bin/machine-config-daemon /binaries/machine-config-daemon

RUN \
    mkdir -p /rpms && \
    mv -v /tmp/rpms/$([ -d /tmp/rpms/$(uname -m) ] && echo $(uname -m)/)*.rpm /rpms/ && \
    dnf install -y dnf-plugins-core && \
    dnf module enable -y cri-o:${CRIO_VERSION} && \
    dnf download -y cri-o cri-tools --destdir /rpms && \
    dnf clean all
