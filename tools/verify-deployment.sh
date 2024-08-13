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

set -e
set -o pipefail

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

for bootstrap in environments/"$ENV"/*bootstrap*
do
    echo "Verify: $bootstrap"
    kustomize_build "$bootstrap"

    for application in "$bootstrap"/*.yaml
    do
        path=$(grep ' path: ' "$application" 2>/dev/null | awk '{print $2}') || continue
        echo "  Verify: $path"
        kustomize_build "$path"
    done
done

