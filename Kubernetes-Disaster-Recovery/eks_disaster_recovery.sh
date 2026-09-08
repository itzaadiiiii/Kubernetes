#!/bin/bash

# === CONFIG ===
CLUSTER_NAME="your-cluster"
NAMESPACE="default"
BACKUP_DIR="./eks-backup-$(date +%F-%H%M)"
REGION="us-east-1"

mkdir -p $BACKUP_DIR

# === BACKUP K8s OBJECTS ===
echo "[*] Exporting cluster objects..."
kubectl get all --all-namespaces -o yaml > "$BACKUP_DIR/all-resources.yaml"
kubectl get pvc --all-namespaces -o yaml > "$BACKUP_DIR/pvcs.yaml"
kubectl get ingress --all-namespaces -o yaml > "$BACKUP_DIR/ingress.yaml"
kubectl get configmap --all-namespaces -o yaml > "$BACKUP_DIR/configmaps.yaml"
kubectl get secret --all-namespaces -o yaml > "$BACKUP_DIR/secrets.yaml"

# === BACKUP EKS CONFIG ===
echo "[*] Backing up EKS cluster config..."
eksctl get cluster --name $CLUSTER_NAME --region $REGION > "$BACKUP_DIR/eksctl-cluster.yaml"

# === VELERO BACKUP (if installed) ===
if command -v velero >/dev/null 2>&1; then
  echo "[*] Triggering Velero backup..."
  velero backup create pre-failure-backup-$(date +%s)
else
  echo "[!] Velero not installed. Skipping volume backup."
fi

echo "[✓] Backup complete. Stored in $BACKUP_DIR"
