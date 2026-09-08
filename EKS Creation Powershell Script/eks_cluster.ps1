# ============================================
# EKS Cluster Deployment - Single Node
# ============================================

$ClusterName = "eks-cluster-1"
$Region = "us-east-1"
$K8sVersion = "1.6"
$Zones = "us-east-1a,us-east-1b,us-east-1c"

$NodeGroup = "eks-cluster-1-ng-1"
$NodeType = "t3.medium"
$Nodes = 1
$NodesMin = 1
$NodesMax = 1
$VolumeSize = 20

# Replace with your EC2 Key Pair name
$SSHKeyName = "YourKeyPair"


# ============================================
# 1. Create EKS Control Plane
# ============================================

Write-Host "`nCreating EKS Control Plane..." -ForegroundColor Cyan

eksctl create cluster `
    --name $ClusterName `
    --version $K8sVersion `
    --region $Region `
    --zones $Zones `
    --without-nodegroup

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create EKS cluster."
    exit 1
}


# ============================================
# 2. Associate OIDC Provider
# ============================================

Write-Host "`nAssociating IAM OIDC Provider..." -ForegroundColor Cyan

eksctl utils associate-iam-oidc-provider `
    --region $Region `
    --cluster $ClusterName `
    --approve

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to associate OIDC provider."
    exit 1
}


# ============================================
# 3. Create Single-Node Managed Node Group
# ============================================

Write-Host "`nCreating Single Node Group..." -ForegroundColor Cyan

eksctl create nodegroup `
    --cluster=$ClusterName `
    --region=$Region `
    --name=$NodeGroup `
    --node-type=$NodeType `
    --nodes=$Nodes `
    --nodes-min=$NodesMin `
    --nodes-max=$NodesMax `
    --node-volume-size=$VolumeSize `
    --ssh-access `
    --ssh-public-key=$SSHKeyName `
    --managed `
    --asg-access `
    --external-dns-access `
    --full-ecr-access `
    --appmesh-access `
    --alb-ingress-access

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create node group."
    exit 1
}


# ============================================
# 4. Update kubeconfig
# ============================================

Write-Host "`nUpdating kubeconfig..." -ForegroundColor Cyan

aws eks update-kubeconfig `
    --region $Region `
    --name $ClusterName


# ============================================
# 5. Verify
# ============================================

Write-Host "`nCluster Info:" -ForegroundColor Green
kubectl cluster-info

Write-Host "`nWorker Nodes:" -ForegroundColor Green
kubectl get nodes -o wide

Write-Host "`nNode Groups:" -ForegroundColor Green
eksctl get nodegroup `
    --cluster $ClusterName `
    --region $Region


Write-Host "`n============================================" -ForegroundColor Green
Write-Host "EKS CLUSTER CREATED SUCCESSFULLY" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green