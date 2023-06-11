### Deploy argo-workflow

[temporary workaround]

Create an overlay or directly replace the ${ARGO_FINAL_URL} string with the url the argo-workflows route will be exposed on.
It is argo-server-${NAMESPACE}.apps.${CLUSTER_NAME}.${BASE_DOMAIN} by default.

[/temporary workaround]

```shell
oc apply -k argo-workflows/operator-deployment
```

### Deploy the okd workflows and build configs

```shell
oc apply -k variants/fcos-multiarch
```

If taints on the secondary architecture nodes are set, annotate the namespace to allow scheduling builds on those nodes

```shell
oc annotate namespace argo-workflows-build-example \
  'scheduler.alpha.kubernetes.io/defaultTolerations'='[{"operator": "Exists", "effect": "NoSchedule", "key": "arm64"}]'
```

To run the workflow from the WorkflowTemplate, create a Workflow object like:

```shell
oc create -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
    generateName: builder-build-workflow-
spec:
  arguments:
    parameters:
    - name: architectures
      value: amd64,arm64
    - name: build-config-name
      value: builder
  workflowTemplateRef:
    name: build-multiarch-image
    clusterScope: true
EOF
```

# Build okd 

```shell
oc create -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
    generateName: okd-build
spec:
  arguments:
    parameters:
    - name: architectures
      value: amd64,arm64
    - name: cleanup
      value: "true" # deletes any previously built images
    - name: os-image
      value: quay.io/okd/centos-stream-coreos-9:4.12-x86_64
    - name: os-name
      value: centos-stream-coreos-9
  workflowTemplateRef:
    name: build-okd
    clusterScope: true
EOF

```

This workflow will import the image at os-image and build the okd release by consuming it.

If, instead, as in the FCOS case, you should build with layering, use the following workflow:

```shell
 oc create -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
    generateName: okd-
spec:
  arguments:
    parameters:
    - name: architectures
      value: amd64,arm64
    - name: cleanup
      value: "false"
    - name: os-buildconfig
      value: fedora-coreos
    - name: os-name
      value: fedora-coreos
    - name: release-image-location 
      value: quay.io/<org>/okd-release-argo:4.13.0-0.okd-2204161150z
    - name: release-mirror-location
      value: quay.io/<org>/okd-release-argo
    - name: registry-credentials-secret-ref
      value: registry-robot-token
  workflowTemplateRef:
    name: build-okd
    clusterScope: true
EOF

```

It takes a os-buildconfig value and lacks the os-image one, so that, at the end of the process, it will build the
os content.

## Package the OKD release (TODO)

## Publish on quay and handle in the origin release-controller? (TODO)

