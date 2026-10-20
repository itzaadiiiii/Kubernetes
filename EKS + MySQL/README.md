# EKS + Amazon RDS MySQL setup

This bundle contains Kubernetes manifests for connecting an application running on EKS to a private Amazon RDS for MySQL database.

## Files

- `00-namespace.yaml` — optional namespace.
- `01-mysql-external-name-service.yaml` — maps Kubernetes service name `mysql` to the RDS endpoint.
- `02-db-secret.yaml` — database credentials (replace placeholders; do not commit real secrets).
- `03-user-management-deployment.yaml` — example application Deployment.
- `04-user-management-service.yaml` — NodePort Service for the example application.
- `05-mysql-client-pod.yaml` — optional temporary MySQL client pod.
- `06-network-check-pod.yaml` — optional troubleshooting pod.
- `99-cleanup.yaml` — removes Kubernetes resources in this bundle.

## Before applying

1. Create RDS MySQL in the same VPC as EKS, with **Public access = No**.
2. Put RDS in a DB subnet group containing private subnets in at least two AZs for Multi-AZ-capable configurations.
3. Configure the RDS security group inbound rule for TCP `3306` from the appropriate EKS node security group or pod security group. **Do not use `0.0.0.0/0`.**
4. Replace the RDS endpoint in `01-mysql-external-name-service.yaml`.
5. Replace the credentials in `02-db-secret.yaml`. For a real deployment, prefer AWS Secrets Manager plus a supported secret integration rather than storing credentials in Git.
6. Replace the image and container port in `03-user-management-deployment.yaml` to match your actual application.
7. Confirm the app supports these environment variables: `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USERNAME`, and `DB_PASSWORD`. Adjust names if your app expects different variables.

## Apply

```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f 02-db-secret.yaml
kubectl apply -f 01-mysql-external-name-service.yaml
kubectl apply -f 03-user-management-deployment.yaml
kubectl apply -f 04-user-management-service.yaml
kubectl -n user-mgmt get pods,svc
```

If your existing manifests are already in a directory, avoid applying both the example Deployment/Service here and duplicate manifests from your own project.

## Create the schema

After the RDS instance is available and network access is configured, run the temporary client:

```bash
kubectl apply -f 05-mysql-client-pod.yaml
kubectl -n user-mgmt exec -it mysql-client -- mysql -h mysql -P 3306 -u dbadmin -p
```

Enter the password interactively, then run:

```sql
CREATE DATABASE userMGMT;
SHOW DATABASES;
EXIT;
```

Remove the client pod when finished:

```bash
kubectl -n user-mgmt delete pod mysql-client
```

## Verify

```bash
kubectl -n user-mgmt get pods,svc,endpoints
kubectl -n user-mgmt logs deployment/user-management
kubectl -n user-mgmt exec deployment/user-management -- printenv DB_HOST
```

`ExternalName` is a DNS alias, not a proxy or network tunnel. DNS resolution alone does not guarantee that security groups, routes, NACLs, TLS settings, or database credentials are correct.

The NodePort example is for learning only. For production, prefer an AWS Load Balancer Controller with an ALB/NLB as appropriate, private worker nodes, TLS, authentication, and restricted ingress. A node's public IP plus NodePort should not be exposed broadly.

## Cleanup

```bash
kubectl delete -f 04-user-management-service.yaml
kubectl delete -f 03-user-management-deployment.yaml
kubectl delete -f 01-mysql-external-name-service.yaml
kubectl delete -f 02-db-secret.yaml
kubectl delete -f 05-mysql-client-pod.yaml --ignore-not-found
kubectl delete -f 00-namespace.yaml
```

This only removes Kubernetes resources. It does **not** delete the RDS database, DB subnet group, or security group. Delete AWS resources separately when you are sure you no longer need them.
