#!/bin/bash

# Copyright 2024-2025 Hewlett Packard Enterprise Development LP
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

while getopts 'ne:h' opt; do
case "$opt" in
e) ENV="$OPTARG" ;;
n) DRYRUN=1 ;;
\?|h)
    echo "Usage: $0 [-n] -e ENVIRONMENT"
    echo
    echo "  -e ENVIRONMENT   Name of environment to deploy".
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

LC_ALL=C
TOC="environments/$ENV/manifest-toc.txt"
API_VERSION_FILES=
FILES_NEEDING_APIVER=

set -e

make kustomize || exit 1

kustomize_build() {
    path="$1"
    if [[ -n $DRYRUN ]]
    then
        echo "bin/kustomize build $path"
    else
        bin/kustomize build "$path" > /dev/null || exit 1
    fi
}

check_use_of_non_hub_api_versions() {
    # Look for any references to an old API, but skip the files that came
    # from the tarball manifest or that are in the reference/ subdir, which
    # is owned by unpack-manifest.

    if ! API_VERSION_FILES=$(find environments/"$ENV" -name api-version.txt); then
        return
    fi
    if [[ ! -f $TOC ]]; then
        echo "Unable to find the manifest table of contents."
        exit 1
    fi
    for apiver_file in $API_VERSION_FILES; do
        apiversion=$(<"$apiver_file")
        apigroup=$(dirname "$apiversion")
        if fnames=$(grep -lr "$apigroup/" environments/"$ENV"); then
            for fname in $fnames; do
                # The reference dir is owned by unpack-manifest.
                [[ $fname == environments/"$ENV"/*/reference/* ]] && continue
                # Skip files that come from the manifest tarball.
                grep -q "$fname" "$TOC" && continue

                if ! grep -q -E "^apiVersion: $apiversion$" "$fname"; then
                    FILES_NEEDING_APIVER="$FILES_NEEDING_APIVER $fname"
                fi
            done
        fi
    done
}

for bootstrap in environments/"$ENV"/*bootstrap*
do
    echo "Verify: $bootstrap"
    kustomize_build "$bootstrap"

    for application in "$bootstrap"/*.yaml
    do
        [[ $application == */kustomization.yaml ]] && continue
        bname=$(basename "$application")
        if ! grep -q "$bname" "$bootstrap/kustomization.yaml"; then
            echo "  Resource $bname is not listed in kustomization.yaml"
            exit 1
        fi
        path=$(grep ' path: ' "$application" 2>/dev/null | awk '{print $2}') || continue
        [[ -z $path ]] && continue
        echo "  Verify: $path"
        kustomize_build "$path"
    done
done

check_use_of_non_hub_api_versions
if [[ -n $FILES_NEEDING_APIVER ]]; then
    echo
    echo "Update these files to ensure their 'apiVersion' value is pointing at"
    echo "the latest API version:"
    for fname in $FILES_NEEDING_APIVER; do
        echo "  $fname"
    done
    echo
    if [[ -n $API_VERSION_FILES ]]; then
        echo "  The 'apiVersion' values should be updated to one of the following:"
        for fname in $API_VERSION_FILES; do
            echo "    $(<"$fname")"
        done
        echo
    fi
    exit 1
fi

