#!/bin/bash -x

GITOPS_LINK="${GITOPS_LINK:=https://github.com/redhat-cop/gitops-catalog.git}"
PULL_SECRET_LOCATION="${PULL_SECRET_LOCATION:-}"
CLONE_FOLDER="${GITOPS_CLONE_FOLDER:=/tmp/gitops}"
CHANNEL="${ACM_CHANNEL:=release-2.4}"
ACM_NAMESPACE="${ACM_NAMESPACE:=open-cluster-management}"
PULL_SECRET_NAME="${PULL_SECRET_NAME:=pull-secret}"

function clone () {
# Provide $1 link to clone
# Provide $2 Directory to clone to
    if [ -d $2 ]
    then
      echo "Directory already exists will not create"
    else
      git clone $1 $2 && echo "Cloned to $2" || exit 1
    fi   
}

function check_secret_exists() {
     oc get secret/$1 -n $2 
}

#Clone Gitops Repo
clone $GITOPS_LINK $CLONE_FOLDER

#Create ACM Operator
oc apply -k $CLONE_FOLDER/advanced-cluster-management/operator/overlays/$CHANNEL

#Create Pull Secret if not exists
check_secret_exists $PULL_SECRET_NAME $ACM_NAMESPACE
secret_status=$?
if [[ -n ${PULL_SECRET_LOCATION} ]] && [[ $secret_status -ne 0  ]]
then
  #Create Pull Secret for ACM
  oc create secret generic $PULL_SECRET_NAME -n $ACM_NAMESPACE \
  --from-file=.dockerconfigjson=$PULL_SECRET_LOCATION \
  --type=kubernetes.io/dockerconfigjson && \
  echo "created Secret" || (echo "Could not create secret")
fi

if [[ $secret_status -eq 0 ]]
then
  #Append Pull Secret to Overlay
  mkdir -p $CLONE_FOLDER/advanced-cluster-management/instance/overlays/secret
  touch $CLONE_FOLDER/advanced-cluster-management/instance/overlays/secret/kustomization.yaml
  echo """
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
 - ../../base 

patches:
  - target:
      kind: MultiClusterHub
      name: multiclusterhub
    patch: |-
      - op: add
        path: /spec
        value: {}
      - op: add
        path: /spec/imagePullSecret
        value: $PULL_SECRET_NAME """ > $CLONE_FOLDER/advanced-cluster-management/instance/overlays/secret/kustomization.yaml
fi

#Create ACM Hub
 oc apply -k $CLONE_FOLDER/advanced-cluster-management/instance/overlays/secret/
