# Beginner guide: the same app on Kubernetes (EKS) with Terraform, Terragrunt, Helm, Kustomize and ArgoCD

This is the Kubernetes version of `../docker-ec2-deploy`. Same Node app, same Docker image. The EC2 + ASG + CodeDeploy servers are replaced by an EKS cluster, and Jenkins/CodeDeploy are replaced by **GitOps**: ArgoCD watches this Git repo and applies whatever is in it.

Region: **ap-south-1 (Mumbai)**. Replace `664418953285` with your account ID everywhere you see it.

What you are building:

```
Terragrunt -> Terraform -> VPC + EKS (Auto Mode) + ECR + ArgoCD          (infra, run once)

docker build/push -> ECR
git push (new image tag) -> GitHub -> ArgoCD -> Kubernetes Deployments -> NLB -> users
```

| Tool | What it does here | Folder |
|---|---|---|
| **Terraform** | Describes the AWS resources (VPC, EKS, ECR, ArgoCD install) | `terraform/modules/` |
| **Terragrunt** | Runs those modules per environment, keeps state in S3, passes outputs between them (VPC -> EKS -> ArgoCD) | `terragrunt/` |
| **Kubernetes** | Plain manifests for the app: a Deployment (pods) and a Service (load balancer) | `kustomize/base/` |
| **Kustomize** | Takes the plain manifests and changes a few things per environment (namespace, replicas, image tag) | `kustomize/overlays/` |
| **Helm** | Another way to package the same app: templates + `values.yaml` | `helm/sample-app/` |
| **ArgoCD** | Runs inside the cluster, pulls this repo and keeps the cluster matching it | `argocd/apps/` |

> Kustomize and Helm do the same job (one app, many environments). Both are here so you can compare them.
> In a real project you would pick one.

---
## Cost warning
This creates real, billed resources. Rough monthly cost in ap-south-1 if you leave it running:
EKS control plane ~$73, NAT gateway ~$35, 3 NLBs (one per app) ~$50, Auto Mode nodes ~$30-60.
**About $200/month. Run the Cleanup phase as soon as you are done.**

## Phase 0 - Install the tools (your laptop or a Linux box)
You need: `aws` CLI v2, `terraform` >= 1.10, `terragrunt` >= 1.0, `kubectl`, `helm` v4, `kustomize` v5, `docker`, `git`.
```bash
aws sts get-caller-identity          # must show your account
terraform version; terragrunt --version; kubectl version --client; helm version; kustomize version
```

## Phase 1 - Look at the layout
```
k8s-eks-deploy/
  terraform/modules/network   VPC: 2 public + 2 private subnets, 1 NAT gateway, subnet tags for load balancers
  terraform/modules/eks       EKS cluster in Auto Mode + ECR repo "sample-app"
  terraform/modules/argocd    ArgoCD (Helm chart) + one "root" Application
  terragrunt/root.hcl         shared: S3 state bucket + AWS provider
  terragrunt/test/env.hcl     environment name + region
  terragrunt/test/{network,eks,argocd}/terragrunt.hcl   one "unit" per module
  kustomize/base              plain Kubernetes YAML
  kustomize/overlays/test     1 replica,  namespace sample-app-test
  kustomize/overlays/prod     3 replicas, namespace sample-app-prod
  helm/sample-app             Helm chart of the same app
  argocd/apps                 3 ArgoCD Applications: kustomize-test, kustomize-prod, helm
```
**EKS Auto Mode** means AWS runs the worker nodes, the load balancer controller and storage for you. There are no node groups to size or patch.

## Phase 2 - Edit the values
1. `terragrunt/test/env.hcl`: `name` and `region`.
2. `terragrunt/test/argocd/terragrunt.hcl`: `repo_url` and `repo_branch` must point at **your** repo and branch (ArgoCD reads it).
3. `argocd/apps/*.yaml`: same `repoURL` / `targetRevision`.
4. Replace the account ID `664418953285` in `kustomize/`, `helm/sample-app/values.yaml`.
5. Commit and push. ArgoCD can only deploy what is on GitHub.

## Phase 3 - Create the infrastructure (Terragrunt)
```bash
cd k8s-eks-deploy/terragrunt/test
terragrunt run --all plan        # shows what will be created; nothing is changed yet
terragrunt run --all apply       # type "y" when asked. Takes ~15-20 minutes (EKS is slow to create)
```
Terragrunt creates the S3 state bucket `tfstate-sample-app-test-<account>-ap-south-1` on first run, then applies
**network -> eks -> argocd** in that order, because each unit has a `dependency` block on the one before.

> `plan` before the cluster exists uses **mock outputs** (fake VPC/cluster IDs) for the later units. That is normal.
> The real values are used on `apply`.

## Phase 4 - Connect kubectl
```bash
aws eks update-kubeconfig --region ap-south-1 --name sample-app-test
kubectl get nodes                 # may be empty - Auto Mode starts nodes only when pods need them
kubectl get pods -n argocd        # all Running after ~2 minutes
```

## Phase 5 - Build and push the image
ECR tags are **immutable** (a tag can never be overwritten), so every build gets a new tag. Start with `1`.
```bash
cd docker-ec2-deploy
ECR=664418953285.dkr.ecr.ap-south-1.amazonaws.com/sample-app
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin ${ECR%%/*}
docker build -t $ECR:1 . && docker push $ECR:1
```
Until this image exists, the app pods show `ImagePullBackOff`. That is expected.

## Phase 6 - Open ArgoCD
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8080:443
```
Open `https://localhost:8080`, user `admin`, the password above. Accept the self-signed certificate warning.
You should see 4 apps: `root` and the 3 it created. All should become **Synced / Healthy**.

## Phase 7 - Open the app
```bash
kubectl get svc -A | grep sample-app      # EXTERNAL-IP column = NLB DNS name (takes ~3 minutes)
curl http://<nlb-dns-name>/               # "Hello from sample-app-... (version test)"
```

## Phase 8 - Deploy a new version (the GitOps way)
Nobody runs `kubectl apply`. You change Git and ArgoCD does the rest.
```bash
docker build -t $ECR:2 docker-ec2-deploy && docker push $ECR:2
cd k8s-eks-deploy/kustomize/overlays/test
kustomize edit set image $ECR:2          # rewrites newTag in kustomization.yaml
git commit -am "test: sample-app 2" && git push
```
ArgoCD checks Git every ~3 minutes (or click **Refresh**) and rolls the pods one by one.
For Helm, change `image.tag` in `helm/sample-app/values.yaml` (or `valuesObject` in `argocd/apps/sample-app-helm.yaml`) instead.

Try **self-heal**: `kubectl -n sample-app-test scale deploy/sample-app --replicas=5`. ArgoCD puts it back to 1 within seconds, because Git says 1.

## Phase 9 - Check your work locally (no cluster needed)
```bash
kustomize build kustomize/overlays/prod        # final YAML for prod
helm lint helm/sample-app && helm template demo helm/sample-app
```

## Troubleshooting
| Problem | What to check |
|---|---|
| `terragrunt` asks to create the S3 bucket | Answer `y`. It stores Terraform state; it is created once |
| Pods `ImagePullBackOff` | Image tag in Git doesn't exist in ECR yet (Phase 5), or wrong account ID |
| Pods `Pending` for minutes | Auto Mode is starting a node; `kubectl get nodeclaims` shows it. Wait ~2 minutes |
| Service `EXTERNAL-IP` stays `<pending>` | Public subnets are missing the `kubernetes.io/role/elb` tag (the network module sets it) |
| ArgoCD app `Unknown` / repo errors | `repoURL` / branch wrong, or the repo is private (add it under Settings -> Repositories) |
| ArgoCD changed back what you edited | That's self-heal. Change Git, not the cluster |
| `kubectl`: `You must be logged in` | Run `aws eks update-kubeconfig` with the same AWS user that ran Terragrunt |
| `push` fails: tag already exists | ECR tags are immutable. Use a new tag number |

## Cleanup (stop charges)
Delete the apps first, so Kubernetes removes the NLBs before the VPC is deleted:
```bash
kubectl -n argocd delete application root    # its finalizer removes the 3 apps and their NLBs
kubectl get svc -A | grep LoadBalancer       # wait until none are left
cd k8s-eks-deploy/terragrunt/test
terragrunt run --all destroy                 # argocd -> eks -> network (reverse order)
```
Finally empty and delete the state bucket `tfstate-sample-app-test-<account>-ap-south-1` in the S3 console.
