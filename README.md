# argocd-boilerplate-1
Boilerplate gitops structure for use with ArgoCD

## Create the site gitops repo

Begin by making a fork of the boilerplate repo to create a new gitops repo for
your site's environments.  Keep one gitops repo for your site, with all of its
environments in the 'main' branch.

**Note** The gitops repo does not use git branches.  Branches are an
anti-pattern for the gitops repo.  A lot has been written about this.  Search
for "gitops branch strategy" to find a sample.

## Create a new environment

To create a new environment in your gitops repo, clone the gitops repo to a local workarea and run `tools/new-env.sh` with the required args.  Push the changes back to github.

If the new environment is named `us-east-1`, then create it with the
following steps.

```bash
git clone git@github.com:NearNodeFlash/site-gitops
cd site-gitops
tools/new-env.sh -e us-east-1 -r https://github.com/NearNodeFlash/site-gitops
git add environments
git commit -m 'create us-east-1'
git push
```

### Bootstrap levels

The new environment will contain a series of directories named `x-bootstrap`, where
`x` indicates a level number.  Each bootstrap directory contains one or more
ArgoCD *AppProject* or *Application* resources, and a `kustomization.yaml` file
to be used by Kustomize.  The Application resources tell ArgoCD how to deploy a
particular service.

Bootstrap level 0 indicates the lowest base upon which the other levels depend,
and in this case it applies the ArgoCD AppProject resource that creates the
"Rabbit" project.  The remaining bootstrap resources are ArgoCD Application
resources.

The bootstrap levels are deployed in ascending order and undeployed in
descending order.  The services are assigned a bootstrap level based on their
dependence on each other.  In general, to undeploy and/or upgrade the services at
a particular level, the bootstraps for any higher levels must be undeployed.

### Populate the new environment in your gitops repo

Obtain the manifest overlay for a given nnf-deploy release. This can be done
by navigating to the Github repo with your browser or by using the Github CLI tool.

To use your browser, navigate to the nnf-deploy repo and click on "Releases" on the right-hand side.  Select the desired release, click to expand the "Assets" for that release, click on the "manifests.tar" to download the manifest.

To use the [Github CLI](https://cli.github.com) tool:

```bash
git clone https://github.com/NearNodeFlash/nnf-deploy.git
cd nnf-deploy
TAG=v0.23.1
TARFILE=/tmp/manifest-$TAG.tar
gh release download -O $TARFILE $TAG
```

Apply the manifest overlay to the gitops repo:

```bash
cd site-gitops
tar xfo $TARFILE -C environments/us-east-1
git add environments/us-east-1
git commit -m "Apply manifests for release $TAG"
git push
```

Add the **SystemConfiguration** resource that describes the hardware in your new
environment:

```bash
cp /path/to/new/us-east-1-systemconfig.yaml environments/us-east-1/nnf-sos/systemconfiguration.yaml
git add environments/us-east-1
git commit -m 'Add SystemConfiguration for us-east-1'
git push
```

Finally, confirm that the manifests hook up properly with Kustomize (see
"Debugging manifests with Kustomize" below) and push the changes to the gitops
repository.

### Deploy bootstraps

Use `tools/deploy-env.sh` to easily deploy the bootstrap resources.

The following will deploy all levels of bootstrap resources for our new
environment, beginning at level 0.  See the command's help output for enabling
a dry-run or for controlling the highest level of bootstrap to be deployed:

```bash
tools/deploy-env.sh -e us-east-1
```

### Undeploy bootstraps

Use `tools/undeploy-env.sh` to easily undeploy the bootstrap resources.  You can
also use the ArgoCD CLI or GUI to delete the Application resources; it is not
necessary to use the undeploy tool.

The following will undeploy all levels of bootstrap resources for
our new environment, beginning at the highest level and stopping before reaching
level 0.  See the command's help output for enabling a dry-run or for
controlling the lowest bootstrap level to be undeployed.

**Note** The default behavior does not undeploy level 0.

```bash
tools/undeploy-env.sh -e us-east-1
```

## Upgrade manifests in an existing environment

Begin any upgrade by first uninstalling the version that is currently running
on the environment.  This may require completing and deleting any existing jobs and
**Workflow** resources.

Upgrade the manifests for an existing environment by unpacking the new manifests over the old:

```bash
cd site-gitops
tar xfo $NEW_TARFILE -C environments/us-east-1
git status
```

Verify that the changes are correct and commit them:

```bash
git diff <...>
git add environments/us-east-1
git commit -m 'Apply manifests for release 0.0.6'
git push
```

Finally, push the changes to the gitops repository so ArgoCD can find them.  If
you are upgrading services whose bootstraps are already deployed then ArgoCD
will notice the updates to the gitops repo and will update the deployed system.

## Configure for KIND

### Create the gitops repo

Create a fork of the boilerplate gitops repo as one of your personal
repositories.  Clone that repo to a local workarea and run `tools/new-env.sh`
with the required args.  Push the changes back to your github fork of the
gitops repo.

Generate a personal token for your personal gitops repo.  To do this, click on
your profile in the upper-right hand corner and select "Settings".  On the
left-hand side, select "Developer Settings", then "Personal access tokens".

* If you choose the "Fine-grained tokens" then under "Repository Permissions" you must allow the "Contents" permission to be "Read-only".
* If you choose the "classic" token then select the "repo" scope.

Use this token to give ArgoCD access to this repository.

### Give the gitops repo token to ArgoCD

Use the token from your personal gitops repo to give ArgoCD access to the repo.
This must be done before you deploy any ArgoCD resources to your cluster.  You
can do this with the `argocd` command or with the GUI.

Using the `argocd` command:

```bash
argocd repo add https://github.com/roehrich-hpe/kind-weds.git --username roehrich-hpe --password $GH_TOKEN --name my-repo
```

Using the ArgoCD GUI, select "Settings" on the left-hand side and then
"Repositories" and then "+Connect Repo" across the top.

## Debugging manifests with Kustomize

After a change to a manifest or kustomization file, inspect the result for correctness
by running kustomize on its containing directory.

```bash
make kustomize
bin/kustomize build environments/example-env/0-bootstrap
bin/kustomize build environments/example-env/dws
```

