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

while getopts 'ne:m:h' opt; do
case "$opt" in
e) ENV="$OPTARG" ;;
m) MANIFEST="$OPTARG" ;;
n) DRYRUN=1 ;;
\?|h)
    echo "Usage: $0 [-n] -e ENVIRONMENT -m MANIFEST"
    echo
    echo "  -e ENVIRONMENT   Name of environment to apply manifests."
    echo "  -m MANIFEST      Name of tarfile containing the release manifest."
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
if [[ -z $MANIFEST ]]; then
    echo "You must specify -m"
    exit 1
elif [[ ! -r $MANIFEST ]]; then
    echo "Unable to read manifest $MANIFEST"
    exit 1
fi

DBG=
[[ -n $DRYRUN ]] && DBG="echo"

set -e
set -o pipefail

$DBG tar xfo "$MANIFEST" -C environments/"$ENV"
exit $?

