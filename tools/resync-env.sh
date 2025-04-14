#!/bin/bash

# Copyright 2025 Hewlett Packard Enterprise Development LP
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

while getopts 'e:h' opt; do
case "$opt" in
e) ENV="$OPTARG" ;;
\?|h)
    echo "Look in environments/example-env for new bootstraps to be added"
    echo "to the specified environment."
    echo 
    echo "Usage: $0 -e ENVIRONMENT"
    echo
    echo "  -e ENVIRONMENT     Name of existing environment to update."
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

set -e
set -o pipefail

echo "Look for new bootstraps in examples-env..."

# First find an existing bootstrap in $ENV and get its GITOPS_REPO value.
GITOPS_REPO=
for bootstrap in environments/"$ENV"/*bootstrap*
do
    for application in "$bootstrap"/*.yaml
    do
        [[ $application == */kustomization.yaml ]] && continue
        if grep -q repoURL: "$application"; then
            GITOPS_REPO=$(grep repoURL: "$application" | awk '{print $2}')
            break
        fi
    done
    [[ -n $GITOPS_REPO ]] && break
done
if [[ -z $GITOPS_REPO ]]; then
    echo "Unable to find a repoURL in the existing bootstraps in environments/$ENV."
    exit 1
fi
S_REPO_URL=$(echo "$GITOPS_REPO" | sed -e 's/\(\/\)/\\\1/g')

customize_one_bootstrap() {
    local yaml_file="$1"

    echo "  Customizing: $yaml_file"
    sed -i.bak \
      -e "s/STAGING_EXAMPLE/$ENV/" \
      -e "s/GITOPS_REPO/$S_REPO_URL/" \
      "$yaml_file" && rm "$yaml_file.bak"
}

customize_bootstraps() {
    local bootstrap_dir="$1"

    for yaml_file in "$bootstrap_dir"/*.yaml
    do
        [[ $yaml_file == */kustomization.yaml ]] && continue
        customize_one_bootstrap "$yaml_file"
    done
}

# Add a new resource to a kustomization.yaml file.
kustomization_new_resource() {
    local resource="$1"
    local kustyaml="$2"

    if ! grep -q "$resource" "$kustyaml"; then
        echo "  Editing: $kustyaml"
        perl -p -i.bak -e 's/^(resources:)$/$1\n- '"$resource"'/' "$kustyaml"
        rm "$kustyaml.bak"
    fi
}

cp_service_dir() {
    local bootstrap="$1"
    local source
    local example_dir

    if ! source=$(grep -E "    path: environments/$ENV/" "$bootstrap" | awk '{print $2}'); then
        echo "Unable to parse source path from $bootstrap"
        exit 1
    fi
    [[ -d "$source" ]] && return
    example_dir=$(echo "$source" | sed -e "s/\/$ENV\//\/example-env\//")
    [[ ! -d "$example_dir" ]] && return
    echo "  Creating: $source"
    cp -r "$example_dir" "$source"
}

cp_service_dirs() {
    local bootstrapd="$1"
    local apl
    local bname

    for apl in "$bootstrapd"/*.yaml
    do
        [[ $apl == */kustomization.yaml ]] && continue
        cp_service_dir "$apl"
    done
}

# Now look for new bootstraps.
NEW_BOOTSTRAP=
for example_bootstrap in environments/example-env/*bootstrap*
do
    echo "Checking: $example_bootstrap"
    bstrapbase=$(basename "$example_bootstrap")
    if [[ ! -d environments/"$ENV/$bstrapbase" ]]; then
        # The whole bootstrap dir is new.
        dest="environments/$ENV/$bstrapbase"
        cp -r "$example_bootstrap" "$dest"
        echo "  Added: $dest"
        customize_bootstraps "$dest"
        NEW_BOOTSTRAP=1
        cp_service_dirs "$dest"
    else
        # Look for new bootstraps in an existing bootstrap dir.
        for application in "$example_bootstrap"/*.yaml
        do
            [[ $application == */kustomization.yaml ]] && continue
            bname=$(basename "$application")
            if ! grep -q "$bname" "$example_bootstrap/kustomization.yaml"; then
                echo "  Error in $example_bootstrap: Resource $bname is not listed in kustomization.yaml"
                echo "  Run: tools/verify-deployment.sh -e example-env"
                exit 1
            fi
            dest="environments/$ENV/$bstrapbase/$bname"
            if [[ ! -e "$dest" ]]; then
                cp "$application" "$dest"
                echo "  Added: $dest"
                customize_one_bootstrap "$dest"
                kustomization_new_resource "$bname" "environments/$ENV/$bstrapbase/kustomization.yaml"
                NEW_BOOTSTRAP=1
                cp_service_dir "$dest"
            fi
        done
    fi
done

if [[ -n $NEW_BOOTSTRAP ]]; then
    echo
    echo "New bootstraps have been added to environments/$ENV."
    echo
    echo "Next steps:"
    echo "  git add environments/$ENV"
    echo "  git commit -m 'New bootstraps in $ENV'"
    echo
    echo "Populate the application directory with a new manifest using"
    echo "tools/unpack-manifest.py."
    echo
    echo "ArgoCD does not monitor bootstraps. The new bootstraps must be deployed"
    echo "with tools/deploy-env.sh."
else
    echo
    echo "No new bootstraps have been added to environments/$ENV."
fi
exit 0
