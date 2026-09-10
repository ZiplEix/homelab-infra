#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo " 🚀 Initialisation Homelab (k3s + GitOps) "
echo "=========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. k3s
echo "⚡ [1/6] Installation / Vérification de k3s..."
if ! command -v k3s &> /dev/null; then
  curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
fi

mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
export KUBECONFIG=~/.kube/config

# 2. Sealed Secrets
echo "🔒 [2/6] Déploiement de Sealed Secrets..."
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/controller.yaml

if ! command -v kubeseal &> /dev/null; then
  echo "📥 Installation de kubeseal CLI..."
  curl -sL https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/kubeseal-0.26.0-linux-amd64.tar.gz | tar -xz kubeseal
  sudo install -m 755 kubeseal /usr/local/bin/kubeseal
  rm kubeseal
fi

# 3. Argo CD
echo "🐙 [3/6] Déploiement d'Argo CD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Patch insecure pour Traefik
kubectl patch deployment argocd-server -n argocd --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--insecure"}
]' || true

# 4. cert-manager
echo "📜 [4/6] Déploiement de cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml

# Patch cert-manager pour utiliser 1.1.1.1 et 8.8.8.8 pour la propagation DNS-01
kubectl -n cert-manager patch deployment cert-manager --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--dns01-recursive-nameservers=1.1.1.1:53,8.8.8.8:53"},
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--dns01-recursive-nameservers-only"}
]' || true

# 5. Attente du démarrage des contrôleurs
echo "⏳ [5/6] Attente du démarrage des pods..."
kubectl rollout status deployment sealed-secrets-controller -n kube-system --timeout=120s
kubectl rollout status deployment argocd-server -n argocd --timeout=180s
kubectl rollout status deployment cert-manager -n cert-manager --timeout=120s
kubectl rollout status deployment cert-manager-webhook -n cert-manager --timeout=120s

# 6. Application des manifests du dépôt
echo "🌐 [6/6] Déploiement des manifests d'infrastructure..."

# RBAC & Instances external-dns
kubectl apply -f "${SCRIPT_DIR}/manifests/01-external-dns/rbac.yaml"

if [ -f "${SCRIPT_DIR}/manifests/01-external-dns/ovh/sealed-secret.yaml" ]; then
  kubectl apply -f "${SCRIPT_DIR}/manifests/01-external-dns/ovh/sealed-secret.yaml"
fi
kubectl apply -f "${SCRIPT_DIR}/manifests/01-external-dns/ovh/deployment.yaml"

if [ -f "${SCRIPT_DIR}/manifests/01-external-dns/cloudflare/sealed-secret.yaml" ]; then
  kubectl apply -f "${SCRIPT_DIR}/manifests/01-external-dns/cloudflare/sealed-secret.yaml"
fi
kubectl apply -f "${SCRIPT_DIR}/manifests/01-external-dns/cloudflare/deployment.yaml"

# ClusterIssuer & Secret cert-manager
if [ -f "${SCRIPT_DIR}/manifests/02-cert-manager/cloudflare-secret.yaml" ]; then
  kubectl apply -f "${SCRIPT_DIR}/manifests/02-cert-manager/cloudflare-secret.yaml"
fi
kubectl apply -f "${SCRIPT_DIR}/manifests/02-cert-manager/cluster-issuer.yaml"

# Ingress Argo CD
kubectl apply -f "${SCRIPT_DIR}/manifests/03-argocd/ingress.yaml"

echo "=========================================="
echo " 🎉 Cluster prêt et sécurisé en HTTPS !"
echo "=========================================="
echo "👉 Mot de passe admin Argo CD :"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo ""
echo "=========================================="
