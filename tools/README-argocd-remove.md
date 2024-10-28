# argocd-remove

Use this if you need to remove ArgoCD and its CRDs. This may be the case if you need to upgrade ArgoCD when the upgrade involves a big jump that may not be easy to handle using the rolling-upgrade procedures described in its docs.

This will not affect the services that ArgoCD was monitoring.

This will remove ArgoCD, the finalizers from each of the ArgoCD Application resources, and then the argoproj.io CRDs.

## Remove the existing ArgoCD

Set your KUBECONFIG environment variable so this tool can find your cluster.

```console
export KUBECONFIG=$config_file
tools/argocd-remove.sh
```

## Install the new ArgoCD

To install a new ArgoCD, update your nnf-deploy workarea to the latest release. The ArgoCD helm chart and matching values override file will be in that workarea.

The nnf-deploy `config/repositories.yaml` file contains the `helm` commandline you will use:

```console
grep helmCmd config/repositories.yaml
```

You will see something like the following:

```bash
    helmCmd: helm install argocd -n argocd --create-namespace argo/argo-cd --version 3.35.4 -f config/helm-values/argocd.yaml
```

Run that commandline, minus the yaml field name, in the nnf-deploy workarea:

```console
helm install argocd -n argocd --create-namespace argo/argo-cd --version 3.35.4 -f config/helm-values/argocd.yaml
```

Verify that the new helm is running by checking the helm chart and the pods:

```console
helm list -n argocd
kubectl get pods -n argocd
```

### Configure the new ArgoCD

Set the password for your new ArgoCD and add your gitops repo to it. Consult the following references:

[Log into ArgoCD](https://github.com/NearNodeFlash/argocd-boilerplate?tab=readme-ov-file#log-into-argocd)

[Add Gitops Repo to ArgoCD](https://github.com/NearNodeFlash/argocd-boilerplate?tab=readme-ov-file#add-gitops-repo-to-argocd)

### Re-deploy the bootstraps

From your gitops repo, re-deploy the ArgoCD "bootstrap" resources (the `AppProject` and `Application` resources). This will allow the new ArgoCD to find your still-running services.

```console
tools/deploy-env.sh -e $ENV
```

Use the ArgoCD CLI to monitor the services:

```console
argocd app list
```
