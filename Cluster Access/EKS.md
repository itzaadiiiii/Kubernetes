### Interview question: How do you connect to your EKS cluster and monitor its health in a production environment?

Answer:

In our environment, we use AWS EKS, where the control plane is AWS-managed and the worker nodes run inside private subnets across multiple Availability Zones for high availability.

Our application workloads are distributed across multiple worker nodes using Kubernetes scheduling, with replicas, HPA, pod anti-affinity and topology spread constraints to maintain availability and distribute workloads.

The Application Load Balancer is deployed in public subnets to receive external application traffic, while worker nodes and application pods run in private subnets. The EKS API endpoint is configured for private access.

For remote employees like us, we follow this access process:

1. AWS SSO: Authenticate through AWS IAM Identity Center using corporate credentials and MFA.
2. AWS Client VPN: Connect to the company's AWS Client VPN, which provides secure connectivity to the private VPC and EKS API endpoint.
3. Verify AWS identity:
   ```
   aws sts get-caller-identity --profile company-dev
   ```
4. Configure EKS access:
   ```
   aws eks update-kubeconfig \
     --region ap-south-1 \
     --name fintech-dev-eks \
     --profile company-dev
   ```
5. Check cluster health:
   ```
   kubectl get nodes
   kubectl get pods -A
   kubectl get deployments -A
   kubectl top nodes
   kubectl top pods -A
   kubectl get events -A
   ```

Once connected, I monitor node health, pod distribution, deployment status, resource utilization and cluster events. For troubleshooting, I use `kubectl describe`, `kubectl logs` and `kubectl logs --previous`.

In short: We use AWS SSO for authentication, AWS Client VPN for secure private network connectivity, and IAM/EKS access entries with Kubernetes RBAC for authorization.

### Quick architecture to remember

```
             Remote DevOps Engineer
                       |
                       v
                Corporate SSO
                       |
                       v
               AWS IAM Identity Center
                       |
                       v
                 AWS Client VPN
                       |
                       v
                  Private VPC
                       |
             +---------+---------+
             |                   |
             v                   v
       Public Subnets       Private Subnets
             |                   |
             v                   v
       Application ALB      EKS Worker Nodes
                                 |
                         +-------+-------+
                         |       |       |
                         v       v       v
                       Pods    Pods    Pods
                         |
                   Kubernetes API
                   (Private Access)
```

One important distinction for interviews: The ALB handles incoming application traffic, whereas kubectl communicates directly with the private EKS API endpoint. Workload distribution across nodes is handled by Kubernetes scheduling and configured availability mechanisms.
