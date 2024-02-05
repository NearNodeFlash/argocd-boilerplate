# Example for a staging environment

This contains the boilerplate for an example environment or cluster named "staging".

The numbered bootstrap directories contain ArgoCD **Application** resources and
are meant to be applied in order.  The higher-numbered directories often
depend on services from the lower-numbered directories.  The lower-numbered
directories are usually for services that change less often.

See the ArgoCD [Applications](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#applications)
and [Application Specification](https://argo-cd.readthedocs.io/en/stable/user-guide/application-specification/)
documentation for more information.
