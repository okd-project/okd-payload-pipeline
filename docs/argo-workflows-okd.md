
## Environment setup

### Deploy Argo Workflows

The kustomization in the `argo-workflows/operator-deployment` folder deploys Argo Workflows in an OKD cluster.

```shell
oc apply -k argo-workflows/operator-deployment
```

You can get the URL of the Argo Workflows as in:
```bash
echo https://$(oc get route -n argo-workflows argo-server -o jsonpath='{.spec.host}')
```

### Deploy the OKD workflows and build configs

You can deploy the Argo Workflows with:

```shell
oc apply -k variants/fcos-multiarch
```

Argo Workflows does not support using a memoization config map outside its deployment namespace.
Therefore, the workflows rely on a memoization configmap that is stored on the `argo-workflows` namespace and some 
service accounts must be allowed working with them.

The default kustomization namespace transformer will replace the `metadata.namespace` of each object and keep any 
RoleBinding's `subjects[0].namespace` as is.

For the `memoization-edit-configmap` RoleBinding, we need the contrary: the `metadata.namespace` field should not change,
the subject's namespace may change.

```shell
oc create -n argo-workflows -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: memoization-edit-configmap
  namespace: argo-workflows
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: edit-config-map
subjects:
  - kind: ServiceAccount
    name: workflows
    namespace: okd-fcos
    # NOTE: Replace the above namespace with your wanted namespace, if changed
EOF
```

#### Expose the internal registry

Although the workflows in this repository do not require it, 
if the registry is not exposed, `oc adm release new` will error out

> only image streams with public image repositories can be the source for a release payload.

```bash
# This needs further investigation
 oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
```

Related PR: https://github.com/openshift/oc/pull/1580

#### Create a secret to store the dockerconfigjson file

Create a secret to host the `dockerconfigjson` file. It will need to be referred when running the workflows:
```shell
oc create -f - <<EOF
kind: Secret
metadata:
  name: registry-robot-token
  namespace: okd-fcos
type: kubernetes.io/dockerconfigjson
stringData:
  .dockerconfigjson: |
    {...the pull secret to allow mirroring to the final payload destination or pull the initial payload...}
```

#### Tainted secondary architecture nodes

Buildconfigs do not allow setting tolerations. If taints on the secondary architecture nodes of your cluster are set, 
annotate the namespace to allow scheduling builds on those nodes:

```shell
oc annotate namespace argo-workflows-build-example \
  'scheduler.alpha.kubernetes.io/defaultTolerations'='[{"operator": "Exists", "effect": "NoSchedule", "key": "arm64"}]'
```

## Build a multiarch image

Given a buildconfig, create the following object to build a multi-arch image.

The image will be pushed to the same location as set in the build config.

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
EOF
```

## Build OKD

### The `mirror-and-customize` WorkflowTemplate

The `mirror-and-customize` `WorkflowTemplate` allows to:
1. Mirror an existing OCP/OKD payload into a local ImageStream object;
2. Remove unwanted ImageStreamTags;
3. Rebuild a list of batched BuildConfigs, see the parameters documentation for the concept of 'batched' BuildConfigs;
4. Package a new release to publish into a given registry.

This workflow orchestrates other specific Argo Workflows templates and is the main block on which the 
`build-okd-from-scratch` and `mirror-and-rebuild-okd` WorkflowTemplates are built on.

### Choose the OS image to use

The workflows in this repo can either consume an already built OKD OS image or build a new one.

Two paramters, `os-image` and `os-buildconfig` are used in mutual exclusion to decide whether to import an already 
built image (`os-image`) or to build one based on the name of a BuildConfig (`os-buildconfig`).

This is usefult to build OKD/SCOS vs OKD/FCOS. 
OKD/FCOS is currently based on the coreos-layering and we can consume an upstream multi-arch image 
for it in a BuildConfig through its [Dockerfile](https://github.com/openshift/okd-machine-os/blob/master/Dockerfile),

OKD/SCOS is built in [okd-project/okd-coreos-pipeline](https://github.com/okd-project/okd-coreos-pipeline) and does 
not have a multi-arch base image to use as base for a layered one yet.

Therefore, builds for OKD/SCOS in this repo should consume an already built SCOS image at time of writing.

#### Parameters

```yaml
    parameters:
      - name: architectures
        description: |
          A comma-separated list of architectures. Nodes for all the architecture must
          be available to run the workflow. For example `arm64,amd64`.
      - name: cleanup
        description: |
          Setting this to 'true' will lead to the deletion of the ImageStreamTags already available and the cleanup of 
          the memoization cache.
        enum:
          - "false"
          - "true"
      - name: os-image
        default: ""
        description: |
          If os-image is not empty,the workflow will import the given ref to the image as `machine-os-content` and 
          with the name given in the `os-name` field. This is alternative to `os-buildconfig`.
        value: ""
      - name: os-name
        enum:
          - fedora-coreos
          - centos-stream-coreos-9
          - rhel-coreos
        description: |
          The name of the OS to be used by the final payload.
      - default: ""
        name: os-buildconfig
        value: ""
        description: |
          The BuildConfig to build the machine-os-content from. This is alternative to `os-image`.
      - name: release-image-location
        description: |
          The destination registry and image to store the release image.
      - name: release-mirror-location
          The destination registry to store the components' images.
      - default: registry-robot-token
        name: registry-credentials-secret-ref
        description: The name of a dockerconfigjson secret to use for authenticating external registries.
      - name: initial-payload
        description: If this parameter is not empty, the workflow will mirror the given payload into the local release ImageStream
      - name: buildconfigs-batched-list
        description: |
          The `buildconfigs-batched-list` represents a list of JSON objects lists.
          Each JSON object is composed by the fields `buildConfig`, `overrideRepoUrl` and `overrideBranch`.
          If `overrideRepoURL` and `overrideBranch` are not empty, they replace the default repositories and ref stored
          in the `BuildConfig`.
          JSON Objects in the same list can run concurrently. Each list of list is guaranteed to run sequentially.
          Therefore, if any BuildConfig A depends on another BuildConfig B, B should be part of a list previously to the 
          one where the build parameters for A are defined.
          [
            [ { "buildConfig": "bc-1", "overrideRepoUrl": "....", "overrideBranch": "my-branch" } ],
            [ { "buildConfig": "bc-2-depending-on-bc-1", "overrideRepoUrl": "....", "overrideBranch": "my-branch" } ]
          ]
      - name: delete-istags
        description: |
          Any ImageStreamTags listed here will be deleted before starting the batched builds.
        value: '[]'
```

#### Generate an OKD payload given an OCP one

You can generate an OKD payload given an already available OCP payload.

Based on the `mirror-and-rebuild-okd` WorkflowTemplate, the following workflow will mirror the entire payload, build
the images differentiating OKD from OCP and package a new release payload.

```
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
      value: "true"
    - name: os-buildconfig
      value: "fedora-coreos"
    - name: os-name
      value: "fedora-coreos"
    - name: os-image
      value: ""
    - name: release-image-location
      value: quay.io/<org>/okd-multi:4.15.0-0.okd-20231014
    - name: release-mirror-location
      value: quay.io/<org>/okd-multi
    - name: registry-credentials-secret-ref
      value: registry-robot-token
    - name: initial-payload
      value: ...
  workflowTemplateRef:
    name: mirror-and-rebuild-okd
EOF
```

## Example: mirror an OKD/OCP payload and customize only some images

If you just want to customize some images in an existing payload, you can use the `mirror-and-cusotmize` WorkflowTemplate.

It is useful to execute custom/manual tests based on specific changes that are not in the master branches yet.

The following example, will build a payload from an initial one (omitted) after replacing the image of the machine config operator 
with the one built by its build config, overriding the repo and branch to use.

```
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
    generateName: ocp-arm64-64k-pagesize-
spec:
  arguments:
    parameters:
    - name: architectures
      value: amd64,arm64
    - name: cleanup
      value: "true"
    - name: os-buildconfig
      value: ""
    - name: os-name
      value: ""
    - name: release-image-location
      value: quay.io/<org>/okd-release-argo:4.15.0-20231014-arm64-64kps
    - name: release-mirror-location
      value: quay.io/<org>/okd-release-argo
    - name: registry-credentials-secret-ref
      value: registry-robot-token
    - name: initial-payload
      value: ....
    - name: buildconfigs-batched-list
      value: |
        [
          [ { "buildConfig": "machine-config-operator", "overrideRepoUrl": "https://github.com/aleskandro/machine-config-operator", "overrideBranch": "cs9-arm64-64k-ps" } ],
        ]
  workflowTemplateRef:
    name: mirror-and-customize
EOF
```

### Build from scratch

The `build-okd-from-scratch` WorkflowTemplate will build an OKD payload from scratch. All the components are rebuilt.

#### Example: use an externally built OS image

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
    name: build-okd-from-scratch
EOF

```

#### Example: use a build config for building the OS

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
    name: build-okd-from-scratch
EOF
```
