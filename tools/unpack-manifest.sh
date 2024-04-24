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
    echo "  -e ENVIRONMENT   Name of environment to unpack manifests."
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

if ! $DBG tar xfo "$MANIFEST" -C environments/"$ENV"; then
    echo "Unable to unpack the manifests"
    exit 1
fi

[[ -n $DRYRUN ]] && exit 0

REFERENCES_DIR="environments/$ENV/nnf-sos/reference"
DEFAULT_PROF="environments/$ENV/nnf-sos/default-nnfstorageprofile.yaml"
TEMPLATE_PROF="$REFERENCES_DIR/template-nnfstorageprofile.yaml"
TEMPLATE_IS_UPDATED=

# extract_template_nnfstorageprofile extracts and saves a copy of the
# NnfStorageProfile/template resource.
function extract_template_nnfstorageprofile {
    local sos_examples="environments/$ENV/nnf-sos/nnf-sos-examples.yaml"

    mkdir -p "$REFERENCES_DIR" || exit 1

    # Wishing for yq(1)...
    if ! python3 - "$sos_examples" <<END > "$TEMPLATE_PROF"
import yaml, sys
with open(sys.argv[1], 'r') as file:
    docs = yaml.safe_load_all(file)
    for doc in docs:
        if doc['kind'] == 'NnfStorageProfile' and doc['metadata']['name'] == 'template':
            print(yaml.dump(doc))
            break
END
    then
        echo "Unable to extract NnfStorageProfile/template: $TEMPLATE_PROF"
        exit 1
    fi

    # Have we updated an existing NnfStorageProfile/template?
    if out=$(git diff "$TEMPLATE_PROF" 2> /dev/null); then
        [[ -n $out ]] && TEMPLATE_IS_UPDATED=yes
    fi
    true # Don't let the if-block above return a failure to our caller.
}

# default_nnfstorageprofile creates NnfStorageProfile/default from
# NnfStorageProfile/template, making the new resource the default profile.
function default_nnfstorageprofile {
    # Wishing for yq(1)...
    if ! python3 - "$TEMPLATE_PROF" <<END > "$DEFAULT_PROF"
import yaml, sys
with open(sys.argv[1], 'r') as file:
    doc = yaml.safe_load(file)
    if doc['kind'] != 'NnfStorageProfile' or doc['metadata']['name'] != 'template':
        print("Unexpected content in $TEMPLATE_PROF", file=sys.stderr)
        sys.exit(1)
    doc['data']['default'] = True
    ns = doc['metadata']['namespace']
    del(doc['metadata'])
    doc['metadata'] = {"name": "default", "namespace": ns}
    print(yaml.dump(doc))
END
    then
        echo "Unable to create default NnfStorageProfile: $DEFAULT_PROF"
        exit 1
    fi
}

# Extract the new NnfStorageProfile/template and save it so it's easy to
# see whether it had any updates in this manifest.
extract_template_nnfstorageprofile

# Create NnfStorageProfile/default only if it does not already exist.
if [[ ! -f $DEFAULT_PROF ]]; then
    default_nnfstorageprofile
elif [[ -n $TEMPLATE_IS_UPDATED ]]; then
    echo
    echo "NOTE:"
    echo "  Inspect the changes to $TEMPLATE_PROF"
    echo "  for any updates that you may need to add to $DEFAULT_PROF."
    echo
fi

if crds=$(git status "environments/$ENV" | grep -E '\-crds.yaml$'); then
    if [[ -n $crds ]]; then
        echo
        echo "NOTE:"
        echo "  The following manifests show CRD changes. Before pushing these"
        echo "  changes to your gitops repo you should remove all jobs and"
        echo "  workflows from the Rabbit cluster and undeploy the Rabbit"
        echo "  software from the cluster by removing the ArgoCD Application"
        echo "  resources (the bootstrap resources)."
        echo "  Consult 'tools/undeploy-env -C' to remove all Rabbit software"
        echo "  CRDs from the cluster."
        echo
        # shellcheck disable=SC2066
        for x in "$crds"; do
            echo "  $x"
        done
        echo
    fi
fi

