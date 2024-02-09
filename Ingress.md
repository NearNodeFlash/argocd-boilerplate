# Ingress to the Helm and ArgoCD services

A starting point for options for accessing the ArgoCD server can be found in
the ArgoCD docs under [Access The Argo CD API
Server](https://argo-cd.readthedocs.io/en/stable/getting_started/#3-access-the-argo-cd-api-server).

In this document we'll use port forwarding for ingress.

## Port Forwarding

Kubectl port-forwarding is a simple way to access a cluster.  Begin by setting
your kubeconfig context to the desired cluster and then establish the port-forwarding:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

## ArgoCD GUI

Point your browser at `http://localhost:8080`.

Obtain the password by using the CLI as described below.  The username will be `admin`.

## ArgoCD CLI

On a Mac you can install the CLI with `brew install argocd`.

Obtain the ArgoCD initial password.  You can use this password when logging in
via the CLI or the GUI:

```bash
argocd admin initial-password -n argocd
```

See [Login Using the CLI](https://argo-cd.readthedocs.io/en/stable/getting_started/#4-login-using-the-cli) in the ArgoCD docs for guidance on setting a new password.

Tell ArgoCD that you are using port-forwarding:

```bash
export ARGOCD_OPTS='--port-forward --port-forward-namespace argocd'
```

Login with the CLI.  The username will be `admin` and the password is the initial password you obtained above:

```bash
argocd login --plaintext 127.0.0.1:8080
```

### Common ArgoCD CLI commands

List the Applications that have been installed:

```bash
argocd app list
```

Get the details of an Application from that list.  In this case, we want to
look at the detail of the DWS Application:

```bash
argocd app get argocd/1-dws
```

## Helm

On a Mac, you can install helm with `brew install helm`.

To see the ArgoCD helm chart that is installed by `nnf-deploy init`:

```bash
helm list -n argocd
```
