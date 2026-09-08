# Here's a step-by-step guide to set up Karpenter on your existing EKS cluster, assuming:

Your EKS cluster is already running.

You have kubectl, aws, and helm installed and configured on your local machine.

You're connected to the cluster via kubeconfig.

# 🚀 Step-by-Step: Set Up Karpenter on EKS (Post Cluster Setup)

## ✅ Step 1: Environment Setup

> export CLUSTER_NAME=<your-cluster-name>
export AWS_REGION=<your-region>  # e.g. us-east-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

## ✅ Step 2: Create Karpenter Namespace
> kubectl create namespace karpenter
> 
## ✅ Step 3: Create IAM Role for Karpenter Controller (with IRSA)
.
> eksctl create iamserviceaccount \
  --cluster $CLUSTER_NAME \
  --name karpenter \
  --namespace karpenter \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore \
  --approve \
  --override-existing-serviceaccounts \
  --region $AWS_REGION

This creates an IAM role linked to the karpenter ServiceAccount via IRSA.

## ✅ Step 4: Create Instance Profile for Karpenter Nodes

> aws iam create-instance-profile --instance-profile-name KarpenterNodeInstanceProfile-$CLUSTER_NAME

> aws iam add-role-to-instance-profile \
  --instance-profile-name KarpenterNodeInstanceProfile-$CLUSTER_NAME \
  --role-name <YourNodeIAMRoleName>  # use the same IAM role used by existing nodes
  
You can find your node IAM role from:

> eksctl get iamidentitymapping --cluster $CLUSTER_NAME
## ✅ Step 5: Install Karpenter with Helm

> helm repo add karpenter https://charts.karpenter.sh
helm repo update
### Install Karpenter:

> helm install karpenter karpenter/karpenter \
  --namespace karpenter \
  --set serviceAccount.create=false \
  --set serviceAccount.name=karpenter \
  --set controller.clusterName=$CLUSTER_NAME \
  --set controller.clusterEndpoint=$(aws eks describe-cluster \
      --name $CLUSTER_NAME \
      --region $AWS_REGION \
      --query "cluster.endpoint" --output text) \
  --set controller.aws.defaultInstanceProfile=KarpenterNodeInstanceProfile-$CLUSTER_NAME
## ✅ Step 6: Tag Your Subnets and Security Groups
Karpenter needs to discover these:
### Tag Subnets
> aws ec2 describe-subnets --filters "Name=tag:aws:eks:cluster-name,Values=$CLUSTER_NAME" \
  --query 'Subnets[*].SubnetId' --output text | tr '\t' '\n' | while read subnet; do
    aws ec2 create-tags --resources $subnet \
      --tags Key=karpenter.sh/discovery,Value=$CLUSTER_NAME

done

### Tag Security Groups (usually EKS control plane SG)
> aws ec2 describe-security-groups \
  --filters Name=tag:aws:eks:cluster-name,Values=$CLUSTER_NAME \
  --query 'SecurityGroups[*].GroupId' --output text | tr '\t' '\n' | while read sg; do
    aws ec2 create-tags --resources $sg \
      --tags Key=karpenter.sh/discovery,Value=$CLUSTER_NAME

done
## ✅ Step 7: Create a Provisioner (YAML)
### karpenter-provisioner.yaml
> apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: default
spec:
  requirements:
    - key: "node.kubernetes.io/instance-type"
      operator: In
      values: ["m5.large", "r5.large"]
  provider:
    subnetSelector:
      karpenter.sh/discovery: <your-cluster-name>
    securityGroupSelector:
      karpenter.sh/discovery: <your-cluster-name>
  ttlSecondsAfterEmpty: 30

Apply it:

> kubectl apply -f karpenter-provisioner.yaml

## ✅ Step 8: Test Karpenter Autoscaling
#### sample-deployment.yaml
> apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
spec:
  replicas: 5
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      containers:
        - name: inflate
          image: public.ecr.aws/eks-distro/kubernetes/pause:3.2
          resources:
            requests:
              memory: "1Gi"
              cpu: "500m"

Apply:

> kubectl apply -f sample-deployment.yaml

This will trigger Karpenter to provision EC2 instances dynamically.

## ✅ Step 9: Validate

> kubectl get nodes -o wide
> kubectl get pods -A
> kubectl get provisioners

## ✅ Optional: Enable Consolidation
If you want Karpenter to optimize by replacing underutilized nodes:

> consolidation:
    enabled: true

Add this to your provisioner spec.

# 🧠 Interview Summary
### "I configured Karpenter on EKS by assigning IRSA-based IAM roles, tagging resources for discovery, and installing Karpenter using Helm. We defined custom provisioners with instance type restrictions and TTLs for node expiration. Karpenter now handles our burst workloads with intelligent node provisioning, improving scaling responsiveness and cost efficiency."
