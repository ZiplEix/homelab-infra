# Gestion des Secrets avec Sealed Secrets

Tous les secrets (tokens d'API, mots de passe BDD, clés JWT, variables Firebase) sont versionnés directement dans Git grâce à **Sealed Secrets**.

Le chiffrement est asymétrique : seule la clé privée présente dans le contrôleur du cluster k3s peut déchiffrer les données.

## Procédure pour chiffrer un secret

### 1. Variables classiques en ligne de commande
Depuis un poste ayant accès au cluster k3s (ou via `kubeseal --fetch-cert`) :

```bash
kubectl create secret generic mon-app-secrets \
  --namespace default \
  --from-literal=JWT_SECRET="secret-tres-robuste" \
  --from-literal=PORT="8080" \
  --dry-run=client -o yaml | kubeseal --format=yaml > k8s/mon-app/sealed-secret.yaml
```

### 2. Variables sensibles multilignes (ex: Clé privée Firebase / PEM)
Les sauts de ligne ne doivent pas être passés directement dans `--from-literal`. Stocke la clé brute dans un fichier temporaire :

```bash
echo "-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQD...
-----END PRIVATE KEY-----" > /tmp/private-key.pem

kubectl create secret generic mon-app-secrets \
  --namespace default \
  --from-file=FIREBASE_PRIVATE_KEY=/tmp/private-key.pem \
  --from-literal=CLIENT_EMAIL="firebase-adminsdk@..." \
  --dry-run=client -o yaml | kubeseal --format=yaml > k8s/mon-app/sealed-secret.yaml

rm /tmp/private-key.pem
```

Commite ensuite uniquement le fichier `k8s/mon-app/sealed-secret.yaml` dans Git.
