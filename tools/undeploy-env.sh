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

TO_LEVEL=1

while getopts 'ne:l:h:C' opt; do
case "$opt" in
C) DESTROY_CRDS=1 ;;
e) ENV="$OPTARG" ;;
l) TO_LEVEL="$OPTARG" ;;
n) DRYRUN=1 ;;
\?|h)
    echo "Usage: $0 [-n] [-C] [-l LEVEL] -e ENVIRONMENT"
    echo
    echo "  -e ENVIRONMENT   Name of environment to undeploy."
    echo "  -l LEVEL         Undeploy bootstraps down to LEVEL, where LEVEL is"
    echo "                   a number >= 0. The default is to stop at level 1,"
    echo "                   to leave the level 0 bootstraps in place. This"
    echo "                   tool will never undeploy bootstrap directories"
    echo "                   which have a negative number as a suffix."
    echo "  -C               Undeploy whole manifests rather than bootstraps."
    echo "                   This removes Custom Resource Definitions (CRDs)."
    echo "                   Use this after the bootstraps have been undeployed"
    echo "                   and prior to an upgrade that modifies CRDs. This"
    echo "                   honors the [-l LEVEL] arg."
    echo "  -n               Dry run."
    exit 1
    ;;
esac
done
shift "$((OPTIND - 1))"

if [[ -z $ENV ]]; then
    echo "You must specify -e"
    exit 1
elif [[ $ENV =~ / ]]; then
    echo "The environment name must not include a slash character."
    exit 1
elif [[ ! -d environments/$ENV ]]; then
    echo "Environment $ENV does not exist"
    exit 1
fi

if [[ ! $TO_LEVEL =~ ^[0-9]+$ ]]; then
    echo "The -l arg must be a level number"
    exit 1
fi

if ! which python3 >/dev/null 2>&1; then
    echo "Unable to find python3 in PATH"
    exit 1
elif ! python3 -c 'import yaml' 2>/dev/null; then
    echo "Unable to find PyYAML"
    exit 1
fi

LC_ALL=C
DBG=
[[ -n $DRYRUN ]] && DBG="echo"

set -e
set -o pipefail

# Deleting the bootstrap resources, the ArgoCD Application resources, is the
# normal way to undeploy a service. ArgoCD will then delete anything that was
# in the manifest for that service, but it will leave CRDs behind.
delete_bootstraps() {
    for x in $(echo environments/"$ENV"/*bootstrap* | awk '{ for (i=NF; i>0; i--) printf("%s ",$i); printf("\n")}')
    do
        bn=$(basename "$x")
        lvl=${bn%%-*}
        if (( lvl < TO_LEVEL )); then
            break
        fi
        $DBG kubectl delete --ignore-not-found=true -k "$x"
    done
}

_delete_manifest() {
    local APP_YAML="$1"

    # Stop if this Application is still active.
    app_name=$(python3 -c 'import yaml, sys; doc = yaml.safe_load(sys.stdin); print(doc["metadata"]["name"])' < "$APP_YAML")
    if kubectl get application -n argocd "$app_name" 1>/dev/null 2>&1 ; then
        echo "Stopping at active Application resource $app_name."
        exit 1
    fi

    # Find the path to the service this Application resource controls.
    svc_path=$(python3 -c 'import yaml, sys; doc = yaml.safe_load(sys.stdin); print(doc["spec"]["source"]["path"])' < "$APP_YAML")
    if [[ ! -d $svc_path ]]; then
        echo "Application $app_yaml refers to source path $svc_path which cannot be found in this workarea."
        exit 1
    fi

    # Delete this service's manifest. The manifest includes the CRDs.
    KBUILD="bin/kustomize build"
    KDEL="kubectl delete --ignore-not-found=true -f-"
    if [[ -n $DRYRUN ]]; then
        echo "$KBUILD $svc_path | $KDEL"
    else
        $KBUILD "$svc_path" | $KDEL
    fi
}

# Delete the manifests. ArgoCD does not remove CRDs and in most cases one would # not want to have them removed. If the CRD is removed then any resources
# of that type would be deleted, and that would be considered data loss.
# But sometimes we need to torch everything when the CRD version (e.g. v1alpha1)
# has a change.
#
# This removes whole manifests, including the CRDs, in reverse order. It begins
# with the highest-numbered Application resource in the highest-numbered
# bootstrap directory and works down to the lowest-numbered Application
# resource in the lowest-numbered bootstrap directory. It stops when it gets
# to an Application resource that is still active, so it is safe to run this
# repeatedly.
delete_manifests() {
    if [[ ! -x bin/kustomize ]]; then
        if ! make kustomize; then
            echo "Unable to retrieve the kustomize tool."
            exit 1
        fi
    fi

    # For each bootstrap level in reverse order...
    for bootstrap_dir in $(echo environments/"$ENV"/*bootstrap* | awk '{ for (i=NF; i>0; i--) printf("%s ",$i); printf("\n")}')
    do
        bn=$(basename "$bootstrap_dir")
        lvl=${bn%%-*}
        if (( lvl < TO_LEVEL )); then
            break
        fi

        # Within this bootstrap dir get each Application resource in
        # reverse order...
        for app_yaml in $(echo "$bootstrap_dir"/[0-9]*.yaml | awk '{ for (i=NF; i>0; i--) printf("%s ",$i); printf("\n")}')
        do
            if grep -qE '^kind: Application' "$app_yaml"; then
                _delete_manifest "$app_yaml"
            fi
        done
    done
}

if [[ -n $DESTROY_CRDS ]]; then
    delete_manifests
else
    delete_bootstraps
fi

