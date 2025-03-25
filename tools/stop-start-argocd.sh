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

STATE="$1"
if [[ -z $STATE ]]; then
    echo "'up' or 'down'"
    exit 1
fi
if [[ $STATE == "up" ]]; then
    REPLICAS=1
elif [[ $STATE == "down" ]]; then
    REPLICAS=0
else
    echo "'up' or 'down'"
    exit 1
fi

DEPS=$(kubectl get deploy -n argocd --no-headers -o=custom-columns='NAME:.metadata.name')
STS=$(kubectl get statefulset -n argocd --no-headers -o=custom-columns='NAME:.metadata.name')

set -x
for dep in $DEPS; do
    kubectl scale --replicas=$REPLICAS deploy -n argocd "$dep"
done
for sts in $STS; do
    kubectl scale --replicas=$REPLICAS statefulset -n argocd "$sts"
done

