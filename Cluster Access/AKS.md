# Interview-ready answers: EKS vs AKS vs GKE cluster connectivity

The overall architecture and connectivity approach are similar across all three cloud providers. The main differences are authentication, VPN/network connectivity and cluster credential commands.
## 2. Azure AKS

[Базовая архитектура кластера AKS - Azure Architecture Center | Microsoft Learn](https://images.openai.com/static-rsc-4/o_6-A3eAZ4SwnorFquKnRwSRAMz_CBX6OamprKyyF3vMfMNsrfh9LM7lU2062H5v-uQfRuD2M0C6JRRQ6mFHh18s7wvA64476VacBjzZ9vg9hwr3ejFb74Ve4ck2DHI624MmV22A2olOci0ki2LpnetE2s9R24ZvAoHGNBNnmCY?purpose=inline)

[learn.microsoft.com](https://learn.microsoft.com/ru-ru/azure/architecture/reference-architectures/containers/aks/baseline-aks?utm_source=chatgpt.com)

Interview answer:

In Azure, we use AKS with a private cluster configuration. The Kubernetes control plane is managed by Azure, while worker nodes are deployed inside private subnets of the Azure VNet, preferably across multiple Availability Zones where supported.

Application workloads are distributed across node pools using replicas, HPA, pod anti-affinity and topology spread constraints.

For external application traffic, we use an Application Gateway or Azure Load Balancer, depending on the architecture, while application pods remain inside the private network.

For remote employees, we authenticate through Microsoft Entra ID using corporate credentials and MFA, then connect through the corporate VPN or Azure VPN to access the private AKS API endpoint.

After establishing connectivity, we retrieve cluster credentials using Azure CLI and use kubectl to monitor cluster health.

Commands:

```
# Authenticate
az login

# Select subscription
az account set --subscription <subscription-id>

# Retrieve AKS credentials
az aks get-credentials \
  --resource-group fintech-rg \
  --name fintech-aks

# Verify cluster
kubectl get nodes
kubectl get pods -A
kubectl get deployments -A

# Monitor resources
kubectl top nodes
kubectl top pods -A

# Troubleshooting
kubectl get events -A
kubectl describe nodes
```

Check whether the cluster uses a private API endpoint:

```
az aks show \
  --resource-group fintech-rg \
  --name fintech-aks \
  --query "{private:apiServerAccessProfile.enablePrivateCluster,privateFQDN:privateFqdn}"
```

Remember: Azure VPN provides network connectivity, Entra ID handles authentication, and Azure RBAC or Kubernetes RBAC controls authorization.

Remember: Cloud VPN provides private network connectivity, Google Cloud IAM handles identity, and Kubernetes RBAC controls cluster-level permissions.

## 4. Quick comparison for interviews

| Area                      | AWS EKS                     | Azure AKS                                 | Google GKE                                  |
| ------------------------- | --------------------------- | ----------------------------------------- | ------------------------------------------- |
| Managed control plane     | AWS                         | Azure                                     | Google                                      |
| Worker nodes              | EC2                         | Azure VMs                                 | Compute Engine                              |
| Identity                  | IAM Identity Center         | Entra ID                                  | Cloud IAM                                   |
| Remote connectivity       | AWS Client VPN              | Azure VPN / corporate VPN                 | Cloud VPN / corporate VPN                   |
| CLI authentication        | `aws sso login`             | `az login`                                | `gcloud auth login`                         |
| Get credentials           | `aws eks update-kubeconfig` | `az aks get-credentials`                  | `gcloud container clusters get-credentials` |
| Application load balancer | AWS ALB                     | Azure Application Gateway / Load Balancer | Google Cloud Load Balancer                  |
| Kubernetes access         | kubectl                     | kubectl                                   | kubectl                                     |

## 5. One common answer applicable to all three clouds

If the interviewer asks, "How do you access and manage private Kubernetes clusters when working remotely?"

You can say:

"In our environment, we deploy Kubernetes worker nodes across private subnets and multiple Availability Zones to ensure high availability. Application workloads are distributed using replicas, HPA and pod topology constraints, while external application traffic enters through cloud load balancers deployed in public-facing network configurations.

Since we work remotely, we first authenticate through our corporate identity provider with MFA and establish private network connectivity using AWS Client VPN, Azure VPN or GCP Cloud VPN, depending on the environment.

Then we retrieve the cluster credentials using the respective cloud CLI, configure our kubeconfig and access the cluster through kubectl.

We use Kubernetes RBAC for authorization and regularly check node health, pod status, deployment availability, resource utilization and cluster events. For troubleshooting, we use kubectl describe, logs and events."

One technical point to remember: Multi-AZ or multi-zone worker placement doesn't automatically guarantee pod distribution. We configure replicas, topology spread constraints, anti-affinity and disruption budgets to achieve the desired availability. Also, the application load balancer and private Kubernetes API endpoint serve two entirely different purposes.
