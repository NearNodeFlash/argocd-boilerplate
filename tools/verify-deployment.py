#!/usr/bin/env python3

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

import argparse
from curses import echo
import os
import shlex
import subprocess
import sys
import yaml

PARSER = argparse.ArgumentParser()
PARSER.add_argument(
    "--env",
    "-e",
    type=str,
    required=True,
    help="Name of environment to verify.",
)
PARSER.add_argument(
    "-n",
    action="store_true",
    dest="dryrun",
    help="Dry run.",
)


def main():
    """main"""

    args = PARSER.parse_args()
    if "/" in args.env:
        print("The environment name must not include a slash character.")
        sys.exit(1)
    env_dir = f"environments/{args.env}"
    if os.path.isdir(env_dir) is False:
        print(f"Environment {env_dir} does not exist.")
        sys.exit(1)

    if args.env != "example-env":
        try:
            make_kustomize(args)
        except RuntimeError as ex:
            print(ex)
            sys.exit(1)

    if verify_bootstraps(args):
        sys.exit(1)

    if args.env == "example-env":
        print("No further checks for example-env.")
        sys.exit(0)

    table_of_contents = f"environments/{args.env}/manifest-toc.txt"
    if check_use_of_non_hub_api_versions(args, table_of_contents):
        sys.exit(1)


def make_kustomize(args):
    """
    Install the kustomize tool.
    """
    cmd = "make kustomize"
    try:
        _ = run_this(args, cmd)
    except RuntimeError as ex:
        raise RuntimeError(f"Unable to install kustomize: {ex}") from ex


def kustomize_build(args, path):
    """
    Run 'kustomize build' to find manifest errors.
    """
    if args.env == "example-env":
        return
    cmd = f"bin/kustomize build {path}"
    if args.dryrun:
        print(cmd)
    else:
        try:
            _ = run_this(args, cmd)
        except RuntimeError as ex:
            raise RuntimeError(f"{cmd}: {ex}") from ex


def verify_resources_in_kustomization(kustomization_file, application_files):
    """
    Verify that all application files are listed in the kustomization.yaml resources.
    """
    err_cnt = 0
    with open(kustomization_file, "r", encoding="utf-8") as f:
        try:
            doc = yaml.safe_load(f)
        except yaml.YAMLError as ex:
            print(f"YAML error in {kustomization_file}: {ex}")
            return 1
        resources = doc["resources"]
        for app in application_files:
            if app not in resources:
                print(f"  Resource {app} not listed in {kustomization_file}")
                err_cnt += 1
    return err_cnt


def verify_application_resource(args, application_file):
    """
    Verify that the application resource is valid and that the path it
    points to has a valid kustomization.
    """
    with open(application_file, "r", encoding="utf-8") as f:
        try:
            doc = yaml.safe_load(f)
        except yaml.YAMLError as ex:
            print(f"YAML error in {application_file}: {ex}")
            return False
        if "kind" not in doc or doc["kind"] != "Application":
            return True
        if "spec" not in doc:
            print(f"spec missing in {application_file}")
            return False
        spec = doc["spec"]
        if "source" not in spec or "path" not in spec["source"]:
            print(f"spec.source or spec.source.path missing in {application_file}")
            return False
        if args.dryrun:
            return True
        path = spec["source"]["path"]
        print(f"  Verify {path}")
        kustomize_build(args, path)
    return True


def verify_bootstraps(args):
    """
    Look for manifest errors in the bootstrap resources.
    """
    errs = 0
    env_dir = f"environments/{args.env}"
    for dirname in os.listdir(env_dir):
        bootstrap_dir = os.path.join(env_dir, dirname)
        if os.path.isdir(bootstrap_dir) and "bootstrap" in dirname:
            print(f"Verify {bootstrap_dir}")
            kustomize_build(args, bootstrap_dir)

            application_files = [
                f
                for f in os.listdir(bootstrap_dir)
                if f.endswith(".yaml") and f != "kustomization.yaml"
            ]
            kustomization_file = f"{bootstrap_dir}/kustomization.yaml"
            err_cnt = verify_resources_in_kustomization(
                kustomization_file, application_files
            )
            errs += err_cnt
            if err_cnt == 0:
                for app in application_files:
                    application_file = os.path.join(bootstrap_dir, app)
                    if not verify_application_resource(args, application_file):
                        errs += 1
    return errs > 0


def check_file_using_apigroup(api_group, api_hub_version, filepath, needs_api_check):
    """
    Check if the given file uses the specified API group.
    """
    with open(filepath, "r", encoding="utf-8") as f:
        try:
            docs = yaml.safe_load_all(f)
        except yaml.YAMLError as ex:
            print(f"YAML error in {filepath}: {ex}")
            return 1
        for doc in docs:
            if "apiVersion" in doc and doc["apiVersion"].startswith(api_group):
                if doc["apiVersion"] != api_hub_version:
                    needs_api_check.append(filepath)
                    return 1
    return 0


def check_files_using_apigroup(args, api_hub_version, toc_files, needs_api_check):
    """
    Look for any references to the given API group, excluding files
    that are in the table of contents or in the reference/ subdir.
    """
    errs = 0
    api_group = os.path.dirname(api_hub_version)
    cmd = f'grep -lr "{api_group}/" environments/{args.env}'
    try:
        files_using_apigroup = run_this_always(cmd)
    except RuntimeError as ex:
        raise RuntimeError(f"{cmd}: {ex}") from ex
    for filepath in files_using_apigroup.splitlines():
        if (
            filepath in toc_files
            or "/reference/" in filepath
            or not filepath.endswith(".yaml")
        ):
            continue
        errs += check_file_using_apigroup(
            api_group, api_hub_version, filepath, needs_api_check
        )
    return errs


def display_needs_api_check(needs_api_check, hub_versions):
    """Display files that need API version checks."""
    if len(needs_api_check) > 0:
        print("")
        print("Update these files to ensure their 'apiVersion' value is pointing at")
        print("the latest API version:")
        for f in needs_api_check:
            print(f"  {f}")
        print("")
        if len(hub_versions) > 0:
            print(
                "  The 'apiVersion' values should be updated to one of the following:"
            )
            for v in hub_versions:
                print(f"    {v}")
            print("")


def check_use_of_non_hub_api_versions(args, toc):
    """
    Look for any references to an old API, but skip the files that came
    from the tarball manifest or that are in the reference/ subdir, which
    is owned by unpack-manifest.
    """
    errs = 0
    needs_api_check = []
    hub_versions = []
    toc_files = slurp_toc(toc)
    cmd = f"find environments/{args.env} -name api-version.txt"
    try:
        api_version_files = run_this_always(cmd)
    except RuntimeError as ex:
        raise RuntimeError(f"{cmd}: {ex}") from ex
    for api_ver_file in api_version_files.splitlines():
        with open(api_ver_file, "r", encoding="utf-8") as f:
            api_hub_version = f.read().strip()
            hub_versions.append(api_hub_version)
        errs += check_files_using_apigroup(
            args, api_hub_version, toc_files, needs_api_check
        )
    display_needs_api_check(needs_api_check, hub_versions)
    return errs > 0


def slurp_toc(toc):
    """Read the table of contents file and return a list of files."""
    files = []
    if not os.path.isfile(toc):
        raise FileNotFoundError(toc)
    with open(toc, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            files.append(line)
    return files


def run_this_always(cmd):
    """Run the given command and return its output."""
    res = subprocess.run(
        shlex.split(cmd),
        capture_output=True,
        text=True,
        check=False,
    )
    if res.returncode != 0:
        raise RuntimeError(res.stderr)
    return res.stdout


def run_this(args, cmd):
    """Run the given command and return its output."""
    if args.dryrun:
        print(f"Dryrun: {cmd}")
    else:
        return run_this_always(cmd)
    return None


if __name__ == "__main__":
    main()

sys.exit(0)
