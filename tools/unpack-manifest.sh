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

# NnfStorageProfiles
DEFAULT_PROF="environments/$ENV/nnf-sos/default-nnfstorageprofile.yaml"
TEMPLATE_PROF="$REFERENCES_DIR/template-nnfstorageprofile.yaml"
TEMPLATE_IS_UPDATED=

# NnfDataMovementProfiles
DM_DEFAULT_PROF="environments/$ENV/nnf-sos/default-nnfdatamovementprofile.yaml"
DM_TEMPLATE_PROF="$REFERENCES_DIR/template-nnfdatamovementprofile.yaml"
DM_TEMPLATE_IS_UPDATED=

# extract_template_nnfprofile extracts and saves a copy of the Nnf<type>Profile/template resource.
function extract_template_nnfprofile {
    local sos_examples="environments/$ENV/nnf-sos/nnf-sos-examples.yaml"
    local type=$1
    local def_prof=
    local temp_prof=

    # Set the right variables based on which type: NnfStorageProfile or NnfDataMovementProfile
    if [[ "$type" == "Storage" ]]; then
        def_prof=$DEFAULT_PROF
        temp_prof=$TEMPLATE_PROF
    else
        def_prof=$DM_DEFAULT_PROF
        temp_prof=$DM_TEMPLATE_PROF
    fi

    mkdir -p "$REFERENCES_DIR" || exit 1

    # Wishing for yq(1)...
    if ! python3 - "$sos_examples" <<END > "$temp_prof"
import yaml, sys
with open(sys.argv[1], 'r') as file:
    docs = yaml.safe_load_all(file)
    for doc in docs:
        if doc['kind'] == 'Nnf${type}Profile' and doc['metadata']['name'] == 'template':
            print(yaml.dump(doc))
            break
END
    then
        echo "Unable to extract Nnf${type}Profile/template: $temp_prof"
        exit 1
    fi

    # Have we updated an existing NnfStorageProfile/template?
    if out=$(git diff "$temp_prof" 2> /dev/null); then
        if [[ "$type" == "Storage" ]]; then
            [[ -n $out ]] && TEMPLATE_IS_UPDATED=yes
        else
            [[ -n $out ]] && DM_TEMPLATE_IS_UPDATED=yes
        fi
    fi
    true # Don't let the if-block above return a failure to our caller.
}

# default_nnfstorageprofile creates Nnf<type>Profile/default from Nnf<type>Profile/template, making
# the new resource the default profile.
function default_nnfprofile {
    local type=$1
    local def_prof=
    local temp_prof=

    # Set the right variables based on which type: NnfStorageProfile or NnfDataMovementProfile
    if [[ "$type" == "Storage" ]]; then
        def_prof=$DEFAULT_PROF
        temp_prof=$TEMPLATE_PROF
    else
        def_prof=$DM_DEFAULT_PROF
        temp_prof=$DM_TEMPLATE_PROF
    fi

    # Wishing for yq(1)...
    if ! python3 - "$temp_prof" <<END > "$def_prof"
import yaml, sys
with open(sys.argv[1], 'r') as file:
    doc = yaml.safe_load(file)
    if doc['kind'] != 'Nnf${type}Profile' or doc['metadata']['name'] != 'template':
        print("Unexpected content in $temp_prof", file=sys.stderr)
        sys.exit(1)
    doc['data']['default'] = True
    ns = doc['metadata']['namespace']
    del(doc['metadata'])
    doc['metadata'] = {"name": "default", "namespace": ns}
    print(yaml.dump(doc))
END
    then
        echo "Unable to create default Nnf${type}Profile: $def_prof"
        exit 1
    fi
}

# Extract the new Nnf[Storage|DataMovement]Profile/template and save it so it's easy to see whether
# it had any updates in this manifest.
extract_template_nnfprofile "Storage"
extract_template_nnfprofile "DataMovement"

unset MESSAGES
message_count=0

# Create NnfStorageProfile/default only if it does not already exist.
if [[ ! -f $DEFAULT_PROF ]]; then
    default_nnfprofile "Storage"
elif [[ -n $TEMPLATE_IS_UPDATED ]]; then
    (( message_count = message_count + 1 ))
    MESSAGES="$MESSAGES
NOTE $message_count:
  Inspect the changes to $TEMPLATE_PROF
  for any updates that you may need to add to $DEFAULT_PROF.

"
fi

# Create NnfDataMovementProfile/default only if it does not already exist.
if [[ ! -f $DM_DEFAULT_PROF ]]; then
    default_nnfprofile "DataMovement"
elif [[ -n $DM_TEMPLATE_IS_UPDATED ]]; then
    (( message_count = message_count + 1 ))
    MESSAGES="$MESSAGES
NOTE $message_count:
  Inspect the changes to $DM_TEMPLATE_PROF
  for any updates that you may need to add to $DM_DEFAULT_PROF.

"
fi

if crds=$(git status "environments/$ENV" | grep -E '\-crds.yaml$'); then
    if [[ -n $crds ]]; then
        (( message_count = message_count + 1 ))
        MESSAGES="$MESSAGES
NOTE $message_count:
  The following manifests show CRD changes. Before pushing these
  changes to your gitops repo you should remove all jobs and
  workflows from the Rabbit cluster and undeploy the Rabbit
  software from the cluster by removing the ArgoCD Application
  resources (the bootstrap resources).
  Consult 'tools/undeploy-env -C' to remove all Rabbit software
  CRDs from the cluster.

$crds

"
    fi
fi

if [[ -n $MESSAGES ]]; then
    echo "$MESSAGES"
fi

