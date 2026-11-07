# Interview-ready answers: EKS vs AKS vs GKE cluster connectivity

The overall architecture and connectivity approach are similar across all three cloud providers. The main differences are authentication, VPN/network connectivity and cluster credential commands.

## 3. Google GKE

[google kubernetes engine - GKE master node - Stack Overflow](https://images.openai.com/static-rsc-4/PWphICBEZbkAp4V3Ble0Sik1fKjmVHqeGa4ScBJEiztxSpNks5HQZ6iheWOrdteKFxroHNXYkpKGYOqB7D1y0_oOJUPY6b5ZwkH0eULrVBwxkS0_qK3xHgu7acXEAf1xu0eamz3aZJYteTlrcTC8FeMyJFA-3BBEwles0iy0t-Y?purpose=inline)

[stackoverflow.com](https://stackoverflow.com/questions/54434561/gke-master-node?utm_source=chatgpt.com)

Interview answer:

In GCP, we use GKE with private cluster networking. The control plane is Google-managed, and worker nodes run inside private VPC subnets across multiple zones for high availability.

Our application workloads are distributed across nodes using Kubernetes scheduling, replicas, HPA and topology spread constraints.

External traffic enters through a Google Cloud Load Balancer, while application pods run on private worker nodes.

For remote employees, we authenticate using Google Cloud IAM or corporate identity federation and connect through Cloud VPN or an approved corporate network connected to the VPC.

Once connected, we retrieve the cluster credentials using the gcloud CLI and access the cluster using kubectl.

Commands:

```
# Authenticate
gcloud auth login

# Set project
gcloud config set project <project-id>

# Retrieve cluster credentials
gcloud container clusters get-credentials fintech-gke \
  --region asia-south1

# For private control plane endpoint
gcloud container clusters get-credentials fintech-gke \
  --region asia-south1 \
  --internal-ip

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
