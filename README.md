# Bazel Kubernetes Rules

Travis CI | Bazel CI
:---: | :---:
[![Build Status](https://travis-ci.org/bazelbuild/rules_k8s.svg?branch=master)](https://travis-ci.org/bazelbuild/rules_k8s) | [![Build Status](http://ci.bazel.io/buildStatus/icon?job=rules_k8s)](http://ci.bazel.io/job/rules_k8s)

## Rules

* [k8s_defaults](#k8s_defaults)
* [k8s_object](#k8s_object)

## Overview

This repository contains rules for interacting with Kubernetes
configurations / clusters.

## Setup

Add the following to your `WORKSPACE` file to add the necessary external dependencies:

```python
git_repository(
    name = "io_bazel_rules_docker",
    commit = "{HEAD}",
    remote = "https://github.com/bazelbuild/rules_docker.git",
)

load(
  "@io_bazel_rules_docker//docker:docker.bzl",
  "docker_repositories",
)

docker_repositories()

# This requires rules_docker to be fully instantiated before
# it is pulled in.
git_repository(
    name = "io_bazel_rules_k8s",
    commit = "{HEAD}",
    remote = "https://github.com/mattmoor/rules_k8s.git",
)

load("@io_bazel_rules_k8s//k8s:k8s.bzl", "k8s_repositories")

k8s_repositories()
```

## Kubernetes Authentication

As is somewhat standard for Bazel, the expectation is that the
`kubectl` toolchain is preconfigured to authenticate with any clusters
you might interact with.

For more information on how to configure `kubectl` authentication, see the
Kubernetes [documentation](https://kubernetes.io/docs/admin/authentication/).

### Container Engine Authentication

For Google Container Engine (GKE), the `gcloud` CLI provides a [simple
command](https://cloud.google.com/sdk/gcloud/reference/container/clusters/get-credentials)
for setting up authentication:
```shell
gcloud container clusters get-credentials <CLUSTER NAME>
```

## Examples

### Basic "deployment" objects

```python
load("@io_bazel_rules_k8s//k8s:object.bzl", "k8s_object")

k8s_object(
  name = "dev",
  kind = "deployment",

  # A template of a Kubernetes Deployment object yaml.
  template = ":deployment.yaml",

  # An optional collection of docker_build images to publish
  # when this target is bazel run.  The digest of the published
  # image is substituted as a part of the resolution process.
  images = {
    "gcr.io/rules_k8s/server:dev": "//server:image"
  },
)
```

### Aliasing (e.g. `k8s_deploy`)

In your `WORKSPACE` you can set up aliases for a more readable short-hand:
```python
load("@io_bazel_rules_k8s//k8s:k8s.bzl", "k8s_defaults")

k8s_defaults(
  # This becomes the name of the @repository and the rule
  # you will import in your BUILD files.
  name = "k8s_deploy",
  kind = "deployment",
  cluster = "my-gke-cluster",
)
```

Then in place of the above, you can use the following in your `BUILD` file:

```python
load("@k8s_deploy//:defaults.bzl", "k8s_deploy")

k8s_deploy(
  name = "dev",
  template = ":deployment.yaml",
  images = {
    "gcr.io/rules_k8s/server:dev": "//server:image"
  },
)
```

### Developer Environments

A common practice to avoid clobbering other users is to do your development
against an isolated environment.  Two practices are fairly common-place.
1. Individual development clusters
1. Development "namespaces"

To support these scenarios, the rules support using "stamping" variables to
customize these arguments to `k8s_defaults` or `k8s_object`.

For per-developer clusters, you might use:
```python
k8s_defaults(
  name = "k8s_dev_deploy",
  kind = "deployment",
  cluster = "gke_dev-proj_us-central5-z_{BUILD_USER}",
)
```

For per-developer namespaces, you might use:
```python
k8s_defaults(
  name = "k8s_dev_deploy",
  kind = "deployment",
  cluster = "shared-cluster",
  namespace = "{BUILD_USER}",
)
```

For more information on "stamping", you can see also the `rules_docker`
documentation on stamping [here](
https://github.com/bazelbuild/rules_docker#stamping).


## Usage

This single target exposes a collection of actions.  We will follow the `:dev`
target from the example above.

### Build

Build builds all of the constituent elements, and makes the template available
as `{name}.yaml`.  If `template` is a generated input, it will be built.
Likewise, any `docker_build` images referenced from the `images={}` attribute
will be built.

```shell
bazel build :dev
```

### Resolve

Deploying with tags, especially in production, is a bad practice because they
are mutable.  If a tag changes, it can lead to inconsistent versions of your app
running after auto-scaling or auto-healing events.  Thankfully in v2 of the
Docker Registry, digests were introduced.  Deploying by digest provides
cryptographic guarantees of consistency across the replicas of a deployment.

You can "resolve" your resource `template` by running:

```shell
bazel run :dev
```

The resolved `template` will be printed to `STDOUT`.

This command will publish any `images = {}` present in your rule, substituting
those exact digests into the yaml template, and for other images resolving the
tags to digests by reaching out to the appropriate registry.  Any images that
cannot be found or accessed are left unresolved.

**This process only supports fully-qualified tag names.**  This means you must
always specify tag and registry domain names (no implicit `:latest`).


### Create

Users can create an environment by running:
```shell
bazel run :dev.create
```

This deploys the **resolved** template, which includes publishing images.

### Update

Users can update (replace) their environment by running:
```shell
bazel run :dev.replace
```

Like `.create` this deploys the **resolved** template, which includes
republishing images.  **This action is intended to be the workhorse
of fast-iteration development** (rebuilding / republishing / redeploying).

### Delete

Users can tear down their environment by running:
```shell
bazel run :dev.delete
```

It is notable that despite deleting the deployment, this will NOT delete
any services currently load balancing over the deployment; this is intentional
as creating load balancers can be slow.

### Describe

Users can "describe" their environment by running:

```shell
bazel run :dev.describe
```

<a name="k8s_object"></a>
## k8s_object

```python
k8s_object(name, kind, template)
```

A rule for interacting with Kubernetes objects.

<table class="table table-condensed table-bordered table-params">
  <colgroup>
    <col class="col-param" />
    <col class="param-description" />
  </colgroup>
  <thead>
    <tr>
      <th colspan="2">Attributes</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>name</code></td>
      <td>
        <p><code>Name, required</code></p>
        <p>Unique name for this rule.</p>
      </td>
    </tr>
    <tr>
      <td><code>kind</code></td>
      <td>
        <p><code>Kind, required</code></p>
        <p>The kind of the Kubernetes object in the yaml.</p>
        <p><b>If this is omitted, the <code>create, replace, delete,
          describe</code> actions will not exist.</b></p>
      </td>
    </tr>
    <tr>
      <td><code>cluster</code></td>
      <td>
        <p><code>string, optional</code></p>
        <p>The name of the cluster to which <code>create, replace, delete,
          describe</code> should speak.</p>
        <p><b>If this is omitted, the <code>create, replace, delete,
          describe</code> actions will not exist.</b></p>
      </td>
    </tr>
    <tr>
      <td><code>namespace</code></td>
      <td>
        <p><code>string, optional</code></p>
        <p>The namespace on the cluster within which the actions are
          performed.</p>
        <p><b>If this is omitted, it will default to
          <code>"default"</code>.</b></p>
      </td>
    </tr>
    <tr>
      <td><code>template</code></td>
      <td>
        <p><code>yaml or json file; required</code></p>
        <p>The yaml or json for a Kubernetes object.</p>
      </td>
    </tr>
    <tr>
      <td><code>images</code></td>
      <td>
        <p><code>string to label dictionary; required</code></p>
        <p>When this target is <code>bazel run</code> the images
          referenced by label will be published to the tag key.</p>
       <p>The published digests of these images will be substituted
          directly, so as to avoid a race in the resolution process</p>
      </td>
    </tr>
  </tbody>
</table>


<a name="k8s_defaults"></a>
## k8s_defaults

```python
k8s_defaults(name, kind)
```

A repository rule that allows users to alias `k8s_object` with default values.

<table class="table table-condensed table-bordered table-params">
  <colgroup>
    <col class="col-param" />
    <col class="param-description" />
  </colgroup>
  <thead>
    <tr>
      <th colspan="2">Attributes</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>name</code></td>
      <td>
        <p><code>Name, required</code></p>
        <p>The name of the repository that this rule will create.</p>
        <p>Also the name of rule imported from
          <code>@name//:defaults.bzl</code></p>
      </td>
    </tr>
    <tr>
      <td><code>kind</code></td>
      <td>
        <p><code>Kind, optional</code></p>
        <p>The kind of objects the alias of <code>k8s_object</code> handles.</p>
      </td>
    </tr>
    <tr>
      <td><code>cluster</code></td>
      <td>
        <p><code>string, optional</code></p>
        <p>The name of the cluster to which <code>create, replace, delete,
           describe</code> should speak.</p>
      </td>
    </tr>
    <tr>
      <td><code>namespace</code></td>
      <td>
        <p><code>string, optional</code></p>
        <p>The namespace on the cluster within which the actions are
           performed.</p>
      </td>
    </tr>
  </tbody>
</table>
