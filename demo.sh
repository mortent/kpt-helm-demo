#!/bin/bash
# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

export PROMPT_TIMEOUT=1

########################
# include the magic
########################
. demo-magic.sh

# hide the evidence
clear

pwd

bold=$(tput bold)
normal=$(tput sgr0)

# start demo
clear
p "# fetch Helm chart for Zookeeper"
pe "helm pull bitnami/zookeeper --untar"
pe "mv zookeeper zookeeper-chart"
wait

p "# create the zookeeper package and include the function config"
pe "mkdir zookeeper"
pe "kpt pkg init zookeeper"
pe 'cat <<EOF >zookeeper/helm-fn.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-config
  annotations:
    config.k8s.io/function: |
      container:
        image: gcr.io/kpt-functions/helm-template
    config.kubernetes.io/local-config: "true"
data:
  chart_path: /source
  name: chart
'

p "# use kpt function to hydrate the helm template"
pe "kpt fn run zookeeper --mount type=bind,src=$(pwd)/zookeeper-chart,dst=/source"

p "# add a kustomization file so we can use this package as the base for kustomize overlays"
pe 'cat <<EOF >zookeeper/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
- default/statefulset_chart-zookeeper.yaml
- default/svc_chart-zookeeper-headless.yaml
- default/svc_chart-zookeeper.yaml
EOF
'

p "# commit the kpt package with the hydrated config and publish a new version"
pe "git add zookeeper && git commit -m \"initial version of Zookeeper package\""
pe "git push origin master"
pe "git tag zookeeper/v0.1.0"
pe "git push origin zookeeper/v0.1.0"

pe "# create an overlay to generate the configuration for the dev environment"
pe "mkdir -p envs/dev/zookeeper"
pe 'cat <<EOF >envs/dev/zookeeper/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
- github.com/mortent/kpt-helm-demo/zookeeper?ref=zookeeper/v0.1.0

namePrefix: "dev-"
commonLabels:
  environment: dev
namespace: dev
patchesStrategicMerge:
- |-
  apiVersion: apps/v1
  kind: StatefulSet
  metadata:
    name: chart-zookeeper
    annotations:
      config.kubernetes.io/function: |
        container:
          image: gcr.io/mortent-dev-kube/zookeeper-fn:latest
  spec:
    replicas: 5
EOF
'

p "# generate the hydrated configuration for the dev env"
pe "mkdir -p hydrated/dev/zookeeper"
pe "kustomize build envs/dev/zookeeper | kpt fn run | kpt fn sink hydrated/dev/zookeeper"

