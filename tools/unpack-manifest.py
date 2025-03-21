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

"""Unpack a tarball into the given environment."""

import argparse
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
    help="Name of environment to unpack manifests.",
)
PARSER.add_argument(
    "--manifest",
    "-m",
    type=str,
    required=True,
    help="Name of tarfile containing the release manifest.",
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
    if os.path.isfile(args.manifest) is False:
        print(f"Unable to read manifest {args.manifest}.")
        sys.exit(1)

    previous_release = None
    new_release = None
    try:
        previous_release, new_release = untar_and_extract_toc(args, env_dir)
    except RuntimeError as ex:
        print(ex)
        sys.exit(1)
    upgrade_type = determine_upgrade_type(previous_release, new_release)

    messages = []
    find_and_extract_template_resources(args, env_dir, "nnf-sos", messages)
    find_and_extract_template_resources(args, env_dir, "nnf-dm", messages)

    check_for_crd_updates(args, env_dir, upgrade_type, messages)

    # Last message: Remind the user to run the verification tool.
    messages.append("Run 'tools/verify-deployment.sh'.")
    present_messages(args, env_dir, messages)


def present_messages(args, env_dir, messages):
    """Display the messages on stdout, then store them to a file."""

    def write_messages(fd, messages):
        cnt = 1
        for x in messages:
            fd.write(f"NOTE {cnt}\n\n")
            fd.write(f"  {x}\n\n")
            cnt = cnt + 1

    print("\n")
    write_messages(sys.stdout, messages)
    print("")
    unpack_notes = f"{env_dir}/unpacking-notes.txt"
    print(f"These notes are saved to {unpack_notes}")
    if args.dryrun:
        print("(dryrun skipping write)")
    else:
        with open(unpack_notes, "w", encoding="utf-8") as fu:
            write_messages(fu, messages)


def check_for_crd_updates(args, env_dir, upgrade_type, messages):
    """
    Determine whether any CRDs have been updated, and create appropriate
    advice depending on the upgrade type.
    """
    out = run_this(args, f"git status {env_dir}")
    crd_update = False
    crds = []
    if out is not None:
        for line in out.split("\n"):
            if line.endswith("-crds.yaml"):
                crd_update = True
                crds.append(line)

    if crd_update and upgrade_type == "release-to-release":
        messages.append(
            """**This looks like a release-to-release upgrade.**
  This release includes some CRD changes. However, because this
  appears to be a release-to-release upgrade, it should not be
  necessary to remove all jobs and workflows or to undeploy the
  existing Rabbit software from the cluster."""
        )
    elif crd_update:
        crd_display = "\n".join(crds)
        messages.append(
            f"""**This does NOT look like a release-to-release upgrade.**
  The following manifests show CRD changes. Before pushing these
  changes to your gitops repo you should remove all jobs and
  workflows from the Rabbit cluster and undeploy the Rabbit
  software from the cluster by removing the ArgoCD Application
  resources (the bootstrap resources).
  Consult 'tools/undeploy-env.sh -C' to remove all Rabbit software
  CRDs from the cluster.

  {crd_display}"""
        )


def find_and_extract_template_resources(args, env_dir, component, messages):
    """
    For the given component, extract any "template" resources from its
    "examples" .yaml file. The templates will be stored to a "references"
    directory within the component, and a "default" version of the resource
    will be created within the component, unless the default version already
    exists.
    """

    component_dir = f"{env_dir}/{component}"
    kust_yaml = f"{component_dir}/kustomization.yaml"
    examples_yaml = f"{component_dir}/{component}-examples.yaml"
    references_dir = f"{component_dir}/reference"

    if os.path.isfile(examples_yaml) is False:
        return

    def create_default_resource(doc, name_of_default, default_prof_base, default_prof):
        # Given a template, create its default.
        with open(default_prof, "w", encoding="utf-8") as fd:
            if doc["metadata"]["name"] == "default":
                if "data" in doc and "default" in doc["data"]:
                    doc["data"]["default"] = True
            ns = doc["metadata"]["namespace"]
            del doc["metadata"]
            doc["metadata"] = {"name": name_of_default, "namespace": ns}
            fd.write(yaml.dump(doc))
            fd.write("\n")  # backward compatibility
        messages.append(
            f"A new resource file '{default_prof_base}' has been created in {component_dir}. Please add it to the 'resources' list in {kust_yaml}."
        )

    def extract_template(doc, name, name_of_default):
        # Given a template, extract it and create its default.
        kind = doc["kind"].lower()
        default_prof_base = f"{name_of_default}-{kind}.yaml"
        default_prof = f"{component_dir}/{default_prof_base}"
        templ_prof = f"{references_dir}/{name}-{kind}.yaml"

        if os.path.isdir(references_dir) is False:
            os.mkdir(references_dir)
        template_preexists = os.path.isfile(templ_prof)
        with open(templ_prof, "w", encoding="utf-8") as ft:
            ft.write(yaml.dump(doc))
            ft.write("\n")  # backward compatibility
        template_updated = False
        if template_preexists:
            # Have we updated the existing version of this template?
            diff_stat = run_this(args, f"git diff {templ_prof}")
            if diff_stat is None and args.dryrun:
                print("(dryrun continuing)")
                return
            if len(diff_stat) > 0:
                template_updated = True
        # Do we need to create the template's default?
        if os.path.isfile(default_prof):
            if template_updated:
                messages.append(
                    f"Inspect the changes to {templ_prof} for any updates that you may need to add to {default_prof}."
                )
        else:
            create_default_resource(
                doc, name_of_default, default_prof_base, default_prof
            )

    # Find the template resources.
    with open(examples_yaml, "r", encoding="utf-8") as fe:
        docs = yaml.safe_load_all(fe)
        for doc in docs:
            name = doc["metadata"]["name"]
            name_of_default = None
            # If it's a template then determine its default name.
            if name == "template":
                name_of_default = "default"
            elif name.endswith("-template"):
                name_of_default = f"{name.removesuffix('-template')}-default"

            if name_of_default is not None:
                extract_template(doc, name, name_of_default)


def determine_upgrade_type(previous_release, new_release):
    """
    Characterize the type of upgrade that is happening. Does it look like a
    release-to-release upgrade, or is it something less structured?
    """

    # Do we have enough info to decide?
    if previous_release is None or new_release is None:
        return None
    # Does it look like dev-to-dev, or release-to-dev, or dev-to-release?
    if "0.0.0" in previous_release or "-dirty" in previous_release:
        return None
    if "0.0.0" in new_release or "-dirty" in new_release:
        return None
    # Then it looks like release-to-release.
    return "release-to-release"


def untar_and_extract_toc(args, env_dir):
    """
    Untar the manifest and keep a copy of its table-of-contents.
    """
    manifest_release_txt = f"{env_dir}/manifest-release.txt"
    manifest_toc = f"{env_dir}/manifest-toc.txt"
    previous_release = None
    new_release = None

    if os.path.isfile(manifest_release_txt):
        previous_release = read_first_line(manifest_release_txt)

    cmd = f"tar xfo {args.manifest} -C {env_dir}"
    try:
        _ = run_this(args, cmd)
    except RuntimeError as ex:
        raise RuntimeError(f"Unable to untar {args.manifest}: {ex}") from ex

    if os.path.isfile(manifest_release_txt) is False:
        err = f"Did not find {manifest_release_txt} after untar."
        if args.dryrun is False:
            raise FileNotFoundError(err)
        print(f"{err}: (dryrun continuing)")
    else:
        new_release = read_first_line(manifest_release_txt)

    try:
        extract_table_of_contents(args, env_dir, manifest_toc)
    except RuntimeError as ex:
        raise RuntimeError(
            f"Unable to extract table of contents from {args.manifest}: {ex}"
        ) from ex

    return previous_release, new_release


def extract_table_of_contents(args, env_dir, manifest_toc):
    """Extract the table of contents from the tarball."""
    cmd = f"tar tf {args.manifest}"
    stdout = run_this(args, cmd)
    if stdout is None and args.dryrun:
        return
    with open(manifest_toc, "w", encoding="utf-8") as ft:
        for x in stdout.split("\n"):
            short = x.removeprefix("./")
            if short.endswith("/") is False and len(short) > 0:
                ft.write(f"{env_dir}/{short}\n")


def read_first_line(filename):
    """Read the first line from the file."""
    with open(filename, "r", encoding="utf-8") as fn:
        for line in fn:
            return line.strip()
    return None


def run_this(args, cmd):
    """Run the given command and return its output."""
    if args.dryrun:
        print(f"Dryrun: {cmd}")
    else:
        res = subprocess.run(
            shlex.split(cmd),
            capture_output=True,
            text=True,
            check=False,
        )
        if res.returncode != 0:
            raise RuntimeError(res.stderr)
        return res.stdout
    return None


if __name__ == "__main__":
    main()

sys.exit(0)
