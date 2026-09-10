# Déployer un Nouveau Service (Méthode Pas à Pas)

Pour déployer une nouvelle application (Backend Go, Frontend SvelteKit/Node/Python, etc.) sans jamais toucher manuellement à la machine k3s, suis cette procédure standardisée.

## 1. Structure dans le repo de l'application

À la racine du dépôt GitHub de ton application, crée :
```text
.
├── .github/workflows/build.yml   # Compilation et push vers GHCR
└── k8s/
    ├── sealed-secret.yaml        # Secrets chiffrés (si nécessaire)
    └── app.yaml                  # Deployment + Service + Ingress
```

## 2. Le Workflow GitHub Actions (`.github/workflows/build.yml`)

```yaml
name: Build and Push Docker Image

on:
  push:
    branches: [ "master" ]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./Dockerfile
          push: true
          tags: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
```
> **Important :** Dans l'interface GitHub de ton repo, va dans **Packages**, clique sur le package généré et vérifie dans les **Package settings** qu'il est bien configuré en **Public** pour que k3s puisse le pull sans token d'authentification.

## 3. Le Manifest Unique `k8s/app.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: NOM_APPLICATION
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: NOM_APPLICATION
  template:
    metadata:
      labels:
        app: NOM_APPLICATION
    spec:
      containers:
      - name: web
        image: ghcr.io/zipleix/NOM_IMAGE:latest
        imagePullPolicy: Always
        ports:
        - containerPort: PORT_ECOUTE # ex: 3000 ou 8080
          name: http
        env:
        - name: PORT
          value: "PORT_ECOUTE"
        - name: NODE_ENV
          value: "production"
        # Décommenter si des secrets scellés sont requis :
        # envFrom:
        # - secretRef:
        #     name: NOM_APPLICATION-secrets
---
apiVersion: v1
kind: Service
metadata:
  name: NOM_APPLICATION-svc
  namespace: default
spec:
  ports:
  - port: PORT_ECOUTE
    targetPort: PORT_ECOUTE
    name: http
  selector:
    app: NOM_APPLICATION
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: NOM_APPLICATION-ingress
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
    external-dns.alpha.kubernetes.io/target: 82.67.198.156
spec:
  ingressClassName: traefik
  rules:
  - host: NOM_DOMAINE.baptiste.zip
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: NOM_APPLICATION-svc
            port:
              number: PORT_ECOUTE
  tls:
  - hosts:
    - NOM_DOMAINE.baptiste.zip
    secretName: NOM_DOMAINE-baptiste-zip-tls
```

## 4. Déclaration dans Argo CD

Deux choix possibles pour déclarer le service :

### Méthode A : Déclaration via l'UI Argo CD (Recommandée pour séparer les apps)
1. Va sur `https://argo.baptiste.zip` ➔ **+ NEW APP**.
2. **App Name :** `nom-application`
3. **Project :** `default`
4. **Sync Policy :** `Automatic` (`Prune` + `SelfHeal` cochés).
5. **Repository URL :** URL de ton repo GitHub.
6. **Path :** `k8s` (activer **Directory Recurse** si sous-dossiers).
7. **Cluster :** `https://kubernetes.default.svc`
8. **Namespace :** `default`

### Méthode B : Déclaration via le repo `homelab-infra` (GitOps pur)
Ajoute un fichier `manifests/apps/mon-app.yaml` dans `homelab-infra` :

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mon-app
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: [https://github.com/ZiplEix/mon-app.git](https://github.com/ZiplEix/mon-app.git)
    targetRevision: HEAD
    path: k8s
    directory:
      recurse: true
  destination:
    server: [https://kubernetes.default.svc](https://kubernetes.default.svc)
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```
