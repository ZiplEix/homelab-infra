#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo " 🚀 Initialisation Homelab (k3s + GitOps) "
echo "=========================================="

# 1. k3s
echo "⚡ [1/5] Installation de k3s..."
if ! command -v k3s &> /dev/null; then
  curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
fi

mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
export KUBECONFIG=~/.kube/config

# 2. Sealed Secrets
echo "🔒 [2/5] Déploiement de Sealed Secrets..."
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/controller.yaml

if ! command -v kubeseal &> /dev/null; then
  echo "📥 Installation de kubeseal CLI..."
  curl -sL https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/kubeseal-0.26.0-linux-amd64.tar.gz | tar -xz kubeseal
  sudo install -m 755 kubeseal /usr/local/bin/kubeseal
  rm kubeseal
fi

# 3. Argo CD
echo "🐙 [3/5] Déploiement d'Argo CD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 4. Attente du démarrage
echo "⏳ [4/5] Attente du démarrage des contrôleurs..."
kubectl rollout status deployment sealed-secrets-controller -n kube-system --timeout=120s
kubectl rollout status deployment argocd-server -n argocd --timeout=180s

# 5. Application des manifests d'infra
echo "🌐 [5/5] Application de la configuration external-dns..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kubectl apply -f "${SCRIPT_DIR}/manifests/01-external-dns/rbac.yaml"

# Déploiement OVH
if [ -f "${SCRIPT_DIR}/manifests/01-external-dns/ovh/sealed-secret.yaml" ]; then
  kubectl apply -f "${SCRIPT_DIR}/manifests/01-external-dns/ovh/sealed-secret.yaml"
fi
kubectl apply -f "${SCRIPT_DIR}/manifests/01-external-dns/ovh/deployment.yaml"

# Déploiement Cloudflare
if [ -f "${SCRIPT_DIR}/manifests/01-external-dns/cloudflare/sealed-secret.yaml" ]; then
  kubectl apply -f "${SCRIPT_DIR}/manifests/01-external-dns/cloudflare/sealed-secret.yaml"
fi
kubectl apply -f "${SCRIPT_DIR}/manifests/01-external-dns/cloudflare/deployment.yaml"

echo "=========================================="
echo " 🎉 Cluster prêt et opérationnel !"
echo "=========================================="
echo "👉 Mot de passe admin Argo CD :"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo ""
echo "=========================================="
