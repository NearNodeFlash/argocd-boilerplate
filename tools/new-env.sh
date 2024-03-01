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

while getopts 'r:e:C:h' opt; do
case "$opt" in
C) SYSCONFIG_PATH="$OPTARG" ;;
e) ENV="$OPTARG" ;;
r) REPO_URL="$OPTARG" ;;
\?|h)
    echo "Usage: $0 -e ENVIRONMENT -r REPO_URL [-C SYSCONFIG_PATH]"
    echo
    echo "  -C SYSCONFIG_PATH Path to SystemConfiguration yaml file."
    echo "  -e ENVIRONMENT    Name of new environment to create."
    echo "  -r REPO_URL       Http URL of gitops repo."
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
elif [[ -d environments/$ENV ]]; then
    echo "Environment $ENV already exists"
    exit 1
fi

if [[ -z $REPO_URL ]]; then
    echo "You must specify -r"
    exit 1
elif [[ $REPO_URL != http* ]]; then
    echo "The repo url must be an http or https URL."
    exit 1
fi

if [[ -n $SYSCONFIG_PATH ]]; then
    if [[ ! -r $SYSCONFIG_PATH ]]; then
        echo "The SystemConfiguration yaml is not readable at $SYSCONFIG_PATH"
        exit 1
    fi
    if ! kind=$(yq .kind "$SYSCONFIG_PATH"); then
        echo "The file does not look like a SystemConfiguration yaml: $SYSCONFIG_PATH"
        exit 1
    elif [[ ! $kind = SystemConfiguration ]]; then
        echo "The file does not contain a SystemConfiguration yaml: $SYSCONFIG_PATH"
        exit 1
    fi
fi

set -e
set -o pipefail

echo "Creating the '$ENV' environment..."
cp -r environments/example-env environments/"$ENV"

S_REPO_URL=$(echo "$REPO_URL" | sed -e 's/\(\/\)/\\\1/g')

for yaml_file in environments/"$ENV"/*bootstrap*/*.yaml
do
    sed -i.bak \
      -e "s/STAGING_EXAMPLE/$ENV/" \
      -e "s/GITOPS_REPO/$S_REPO_URL/" \
      "$yaml_file" && rm "$yaml_file.bak"
done

sysconfig_dest="environments/$ENV/nnf-sos/systemconfiguration.yaml"
if [[ -n $SYSCONFIG_PATH ]]; then
    cp "$SYSCONFIG_PATH" "$sysconfig_dest"
else
    echo "Next steps:"
    echo "  Add your SystemConfiguration yaml to $sysconfig_dest"
fi

echo
echo "Next steps:"
echo "  git add environments"
echo "  git commit -m 'Create $ENV'"

