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

while getopts 'ne:l:h' opt; do
case "$opt" in
e) ENV="$OPTARG" ;;
l) TO_LEVEL="$OPTARG" ;;
n) DRYRUN=1 ;;
\?|h)
    echo "Usage: $0 [-n] [-l LEVEL] -e ENVIRONMENT"
    echo
    echo "  -e ENVIRONMENT   Name of environment to undeploy."
    echo "  -l LEVEL         Undeploy bootstraps down to LEVEL, where LEVEL is"
    echo "                   a number >= 0. The default is to stop at level 1,"
    echo "                   to leave the level 0 bootstraps in place."
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

LC_ALL=C
DBG=
[[ -n $DRYRUN ]] && DBG=echo
for x in $(echo environments/"$ENV"/*bootstrap* | awk '{ for (i=NF; i>0; i--) printf("%s ",$i); printf("\n")}')
do
    bn=$(basename $x)
    lvl=${bn%%-*}
    if (( $lvl < $TO_LEVEL )); then
        break
    fi
    $DBG kubectl delete -k "$x"
done

