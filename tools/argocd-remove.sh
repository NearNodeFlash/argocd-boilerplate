#!/bin/bash

# Copyright 2024 Hewlett Packard Enterprise Development LP
# Other additional copyright holders may be indicated within.
#
# The entirety of this work is licensed under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
#
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#-----

# Use this if you need to remove ArgoCD and its CRDs. This may be the case if
# you need to upgrade ArgoCD when the upgrade involves a big jump that may not
# be easy to handle using the rolling-upgrade procedures described in its docs.

# This will not affect the services that ArgoCD was monitoring.

# This will remove ArgoCD, the finalizers from each of the ArgoCD Application
# resources, and then the argoproj.io CRDs.
#
# The procedure:
# - Uninstall the ArgoCD helm chart.
# - Verify that the ArgoCD pods are gone.
# - Run this tool to remove the Application resource finalizers.
# - Delete each of the Application resources.
# - Delete each of the AppProject resources.
# - Delete each of the argoproj.io CRDs.
#
# After this, you may install a new ArgoCD helm chart, set its password, add
# the gitops repository, and re-deploy the AppProject and Application resources
# (the bootstraps). The new ArgoCD will then begin monitoring your still-
# running services.

set -e
set -o pipefail

uninstall_chart() {
    if chart=$(helm list -n argocd -o json | jq -rM '.[0].name' | grep -v null); then
        helm uninstall -n argocd "$chart"
    fi
}

wait_for_pods() {
    local count=10
    local all_gone=1

    while (( count > 0 )); do
        pods=$(kubectl get pods -n argocd --no-headers 2> /dev/null)
        if [[ -z $pods ]] || [[ $(echo "$pods" | wc -l) -eq 0 ]]; then
            all_gone=
            break
        fi
        sleep 1
        (( count = count - 1 ))
    done
    if [[ -n $all_gone ]]; then
        echo "Some ArgoCD pods are still running:"
        echo "$pods"
        exit 1
    fi
}

remove_finalizers() {
    applications=$(kubectl get applications -n argocd --no-headers -o custom-columns=NAME:.metadata.name)

    for app in $applications; do
       [[ $(kubectl get application -n argocd "$app" -o json | jq -M .metadata.finalizers | grep -vc null) -eq 0 ]] && continue

       echo "Patching $app"
       kubectl patch -n argocd Application "$app" -p '{"metadata":{"finalizers":null}}' --type=merge
    done
}

CRDS="argocdextensions applications appprojects"

delete_crds() {
    for crd in $CRDS; do
        kubectl delete crd "$crd.argoproj.io"
    done
}

check_crds() {
    local count=10
    local all_gone=1

    for crd in $CRDS; do
        while (( count > 0 )); do
            if ! kubectl get crd "$crd.argoproj.io" --no-headers 2> /dev/null; then
                all_gone=
                break
            fi
            sleep 1
            (( count = count - 1 ))
        done
        if [[ -n $all_gone ]]; then
            echo "ArgoCD CRD $crd still exists."
            exit 1
        fi
    done
}

uninstall_chart
wait_for_pods
remove_finalizers
delete_crds
check_crds

echo
echo "ArgoCD, and its resources and CRDs, has been removed."
echo

