# Tracking the ArgoCD Boilerplate Repo

While a gitops repo does not use branches for environment or release management,
it is helpful to use a mirror branch for tracking changes to the ArgoCD
boilerplate repo.

## Create a private gitops repo

Create an empty private repo in GH, "gitops-panda". We'll
fill it from the ArgoCD boilerplate.

Initialize the private repo.

```bash
git clone git@github.com:roehrich-hpe/gitops-panda.git
```

Clone nnf-deploy. We'll refer to it for the SystemConfiguration resource for
our KIND environment.

```bash
git clone git@github.com:NearNodeFlash/nnf-deploy.git nnf-deploy
```

## Mirror the ArgoCD boilerplate repo

Hook up your private repo to the ArgoCD boilerplate repo. This will pull the ArgoCD boilerplate commit history into your workarea so we can use it to make a local branch that acts as a mirror.

```bash
cd gitops-panda
git remote add boilerplate-upstream https://github.com/NearNodeFlash/argocd-boilerplate.git
git remote -v show
git fetch boilerplate-upstream
git ls-remote boilerplate-upstream
```

Create two local branches from that ArgoCD boilerplate repo. One will be the branch where you create the environments for your local clusters and the other will be used to mirror the upstream boilerplate repo.

Create them in this order so that `main` will be the default branch in your private repository.

```bash
git checkout boilerplate-upstream/main
git checkout -b main
git push --set-upstream origin main
git checkout -b boilerplate-main
git push --set-upstream origin boilerplate-main
```

## Create a new environment for your KIND cluster

```bash
cd gitops-panda
git checkout main
./tools/new-env.sh -e kind -r https://github.com/roehrich-hpe/gitops-panda.git -C ../nnf-deploy/config/systemconfiguration-kind.yaml -L /path/to/lustrefilesystem.yaml

git add environments
git commit -m 'Create KIND'
```

You can now proceed to unpack a release manifest in this environment.

## To pull in updates from the ArgoCD boilerplate

Hook up the ArgoCD boilerplate repo and fetch its `main` branch into your commit history:

```bash
git remote add boilerplate-upstream https://github.com/NearNodeFlash/argocd-boilerplate.git
git remote -v show
git fetch boilerplate-upstream
git ls-remote boilerplate-upstream
```

Merge the ArgoCD boilerplate's `main` branch into your local mirror of that
branch. You should never make your own changes in this branch, so this
merge should always be clean:

```bash
git checkout boilerplate-main
git pull
git merge boilerplate-upstream/main
git push
```

Merge the boilerplate changes into your `main` branch. This is the branch where
you've been creating your environments. This merge may need some manual fixups
dpending on how much you've deviated from the upstream boilerplate.

```bash
git checkout main
git pull
git merge boilerplate-main
git push
```

Now you should inspect any changes to `environments/example-env` and carry them into the environments you've created for your clusters.

