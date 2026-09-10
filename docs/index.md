# Documentation Homelab k3s GitOps

Bienvenue sur la documentation technique de l'infrastructure homelab auto-hébergée sous Kubernetes (**k3s**), orchestrée de manière déclarative par **Argo CD** selon les principes GitOps.

## Stack Technique

| Composant | Technologie | Rôle |
| :--- | :--- | :--- |
| **Nœud / Hyperviseur** | Proxmox VE / Debian | VM dédiée `k3s-node` (`192.168.1.43`) |
| **Moteur Kubernetes** | k3s v1.30+ | Distribution légère k8s avec Traefik intégré |
| **Ingress Controller** | Traefik v3 | Reverse proxy d'entrée, terminaison TLS |
| **Gestionnaire Certificats** | cert-manager | ACME Let's Encrypt (challenges DNS-01 Cloudflare) |
| **Automatisation DNS** | external-dns | Synchronisation des IP publiques sur Cloudflare |
| **Moteur GitOps** | Argo CD | Réconciliation continue depuis GitHub |
| **Chiffrement Secrets** | Sealed Secrets (Bitnami) | Stockage sécurisé des secrets dans Git |
| **Stockage Persistant** | Local-Path Storage | CSI local pour les bases de données |
