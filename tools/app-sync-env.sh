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

SLP=1

while getopts 's:h' opt; do
case "$opt" in
s) SLP=$OPTARG ;;
\?|h)
    echo "Usage: $0 [-s SLEEP_INTERVAL]"
    echo
    echo "  -s SLEEP_INTERVAL  Sleep interval. Default=$SLP."
    exit 1
    ;;
esac
done
shift "$((OPTIND - 1))"

set -e
set -o pipefail

if ! PROJECTS=$(argocd proj list -o name); then
    echo "Unable to list argocd projects. Do you need to use 'argocd login'?"
    exit 1
fi

sync_proj() {
    local project="$1"
    local cmd

    cmd="argocd app sync --project $project --force"
    echo "$cmd"
    while ! $cmd > /dev/null; do
        sleep "$SLP"
        echo "$cmd"
    done
}

for proj in $PROJECTS; do
    sync_proj "$proj"
done

