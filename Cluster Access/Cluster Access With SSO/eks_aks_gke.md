When your user is created in **Microsoft Entra ID** and permissions are managed in each cloud, your day-to-day workflow splits into two parts: **authenticating your CLI/session** against the cloud, and **fetching cluster credentials** into `kubeconfig` so `kubectl` can talk to the cluster.

### Where Permissions Are Managed in GCP

In GCP, permissions for federated Entra ID users are managed in **Google Cloud IAM** (at the Organization, Folder, or Project level)—specifically via **IAM Role Bindings** targeting your **Workforce Identity Pool** principals/groups—paired with **Kubernetes RBAC** (`RoleBinding` / `ClusterRoleBinding`) inside GKE.

* **Cloud control plane (e.g., `gcloud container clusters get-credentials`):** Controlled by GCP IAM roles such as `roles/container.clusterViewer` or `roles/container.developer`.
* **Inside the GKE cluster (e.g., `kubectl get pods`, `kubectl logs`):** Controlled by Kubernetes RBAC inside GKE (either legacy `RoleBinding`/`ClusterRoleBinding` mapped to the federated group/subject, or GKE RBAC using Google Groups).

---

### Commands You Run on Day 1 Across All Three Clouds

#### 1. AWS (EKS via AWS IAM Identity Center + Permission Sets)

Your Entra ID group is synced via SCIM to **AWS IAM Identity Center** and mapped to a **Permission Set** (which grants AWS IAM permissions and EKS access entries/roles).

```bash
# 1. Authenticate via IAM Identity Center SSO (opens browser / device code)
aws sso login --profile <your-sso-profile>

# 2. Update kubeconfig for the target EKS cluster
aws eks update-kubeconfig \
  --region <aws-region> \
  --name <eks-cluster-name> \
  --profile <your-sso-profile>

# 3. Verify cluster access
kubectl get nodes

```

#### 2. Azure (AKS via Entra ID + Azure RBAC / K8s RBAC)

Your Entra ID account authenticates directly to Azure, and permissions are enforced via **Azure RBAC** (e.g., *Azure Kubernetes Service RBAC Cluster Admin* or *Reader*) and/or Kubernetes RBAC.

```bash
# 1. Sign in to Azure with your Entra ID account
az login

# 2. Select the right subscription (if working across multiple client/env subscriptions)
az account set --subscription <subscription-id-or-name>

# 3. Pull AKS cluster credentials into kubeconfig
az aks get-credentials \
  --resource-group <resource-group-name> \
  --name <aks-cluster-name>

# 4. Run kubectl (kubelogin will prompt Entra ID login if not already cached)
kubectl get nodes

```

#### 3. GCP (GKE via Workforce Identity Federation + GCP IAM / K8s RBAC)

Your Entra ID identity is federated through a **GCP Workforce Identity Pool**, with permissions bound in **GCP IAM** and Kubernetes RBAC.

```bash
# 1. Sign in using your Workforce Identity login config file (provided by platform/admin team)
gcloud auth login --login-config=/path/to/workforce-login-config.json
# Once activated, subsequent logins often just use:
# gcloud auth login

# 2. Set the target GCP project
gcloud config set project <gcp-project-id>

# 3. Fetch GKE cluster credentials into kubeconfig
gcloud container clusters get-credentials <gke-cluster-name> \
  --region <gcp-region> \
  # or --zone <gcp-zone> for zonal clusters

# 4. Run kubectl (uses the gcloud auth plugin in kubeconfig)
kubectl get nodes

```

---

### Quick Interview Comparison

| Cloud | Where Cloud Permissions Live | Auth / Session Command | Kubeconfig Command |
| --- | --- | --- | --- |
| **AWS (EKS)** | **IAM Identity Center** (Permission Sets → IAM Role + EKS Access) | `aws sso login --profile <p>` | `aws eks update-kubeconfig ...` |
| **Azure (AKS)** | **Azure RBAC** (and/or K8s RBAC) on AKS/Subscription | `az login` | `az aks get-credentials ...` |
| **GCP (GKE)** | **GCP IAM** (Workforce Pool bindings) + **K8s RBAC** | `gcloud auth login --login-config=...` | `gcloud container clusters get-credentials ...` |

---

### Ready-to-Use Interview Soundbite

> *"Once my Entra ID user is provisioned and added to the right groups, I don't use static keys or shared kubeconfigs—I authenticate per cloud and pull short-lived cluster credentials.*
> *On **AWS**, permissions come from **IAM Identity Center Permission Sets**, so I run `aws sso login` and then `aws eks update-kubeconfig`. On **Azure**, permissions are managed via **Azure RBAC** (and Kubernetes RBAC), so I run `az login` and `az aks get-credentials`, and `kubelogin` handles the Entra token flow on `kubectl`. On **GCP**, permissions are managed in **GCP IAM** via **Workforce Identity Federation** pool/group bindings alongside Kubernetes RBAC—I log in with `gcloud auth login` using the workforce login config and run `gcloud container clusters get-credentials` before using `kubectl`."*
