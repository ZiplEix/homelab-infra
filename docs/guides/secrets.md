# Secret Management with Sealed Secrets

## Overview

All sensitive parameters (database credentials, JWT private signing keys, API tokens) must be committed to Git alongside application manifests without compromising security.

This cluster uses **Bitnami Sealed Secrets**. The mechanism relies on asymmetric public-key cryptography:

1. **Client-Side:** The public encryption certificate is fetched once by the operator. Secrets are encrypted locally into a custom Kubernetes resource called a `SealedSecret`.
2. **Repository:** The `SealedSecret` can be safely committed to public or private version control repositories.
3. **In-Cluster:** The `sealed-secrets-controller` running inside the cluster holds the private decryption key in memory and decrypts the `SealedSecret` into a native, unencrypted Kubernetes `Secret`.

---

## Encryption Flow

```mermaid
flowchart TD
    subgraph Local [Local Development Machine / Operator]
        Sec[Plaintext K8s Secret]
        Cert[Sealed Secrets Public Certificate]
        KS[kubeseal CLI]
        SS[SealedSecret YAML]
    end

    subgraph Git [Version Control]
        Repo[(GitHub Repository)]
    end

    subgraph Cluster [k3s Cluster Boundary]
        Controller[sealed-secrets-controller]
        PrivKey[(Cluster Private Key: Sealed Secrets Secret)]
        K8sSec[Native Decrypted Kubernetes Secret]
        Pod[Application Pod]
    end

    Sec -->|Piped with Cert| KS
    Cert --> KS
    KS -->|Generates| SS
    SS -->|Git Commit & Push| Repo
    Repo -->|Argo CD Sync| SS
    SS -->|Reconciled by| Controller
    Controller -->|Decrypts via| PrivKey
    Controller -->|Creates / Updates| K8sSec
    K8sSec -->|Mounted via envFrom or volume| Pod
```

---

## Prerequisites

To seal secrets from a local workstation, ensure the `kubeseal` CLI binary is installed:

### Linux / WSL
```bash
KUBESEAL_VERSION="v0.27.0"
curl -OL "[https://github.com/bitnami-labs/sealed-secrets/releases/download/$](https://github.com/bitnami-labs/sealed-secrets/releases/download/$){KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION#v}-linux-amd64.tar.gz"
tar -xvzf kubeseal-${KUBESEAL_VERSION#v}-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
rm kubeseal kubeseal-${KUBESEAL_VERSION#v}-linux-amd64.tar.gz
```

### Windows (PowerShell)
```powershell
winget install Bitnami.Kubeseal
```

---

## Certificate Retrieval

If `kubeseal` has direct `kubectl` access to the cluster context, it automatically retrieves the public certificate during encryption.

If sealing offline or from an isolated pipeline, retrieve and persist the public sealing certificate:

```bash
kubeseal --fetch-cert \
  --controller-name=sealed-secrets \
  --controller-namespace=kube-system > pub-sealed-secrets.pem
```

---

## Sealing Workflows

### 1. Standard Key-Value Pairs

To create a secret containing simple literal strings:

```bash
kubectl create secret generic example-app-secrets \
  --namespace default \
  --from-literal=DB_USER="postgres" \
  --from-literal=DB_PASSWORD="SuperSecurePassword123!" \
  --from-literal=JWT_SECRET="c6b1e626e2e0477eac1f4967ec123456" \
  --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system --format=yaml > k8s/example-app/sealed-secret.yaml
```

---

### 2. Complex & Multiline Payloads (PEM, JSON, Private Keys)

When encoding certificates, SSH keys, or multiline private keys (e.g., Firebase Service Accounts), command-line literals can introduce line-ending or escaping issues. Always stage them in temporary files before sealing.

```bash
# 1. Stage the raw key to a temporary file
cat << 'EOF' > /tmp/private.key
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDabc123...
...multiline content...
-----END PRIVATE KEY-----
EOF

# 2. Generate and seal using --from-file
kubectl create secret generic auth-secrets \
  --namespace default \
  --from-file=PRIVATE_KEY=/tmp/private.key \
  --from-literal=ENVIRONMENT="production" \
  --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system --format=yaml > k8s/auth/sealed-secret.yaml

# 3. Securely remove the unencrypted file
rm -f /tmp/private.key
```

---

## Scoping Models

`kubeseal` enforces access control scopes to prevent a secret encrypted for one workload from being decrypted or hijacked by another:

| Scope | Flag | Behavior |
| :--- | :--- | :--- |
| **Strict (Default)** | *(None)* | Encryption is bound to both the exact **Secret Name** and **Namespace**. Renaming the secret or changing its namespace breaks decryption. |
| **Namespace-wide** | `--scope namespace-wide` | Can be decrypted by any secret resource within the designated namespace. |
| **Cluster-wide** | `--scope cluster-wide` | Can be decrypted anywhere in the cluster across all namespaces. **Use strictly for global root certificates.** |

> **Rule:** Always rely on the default **Strict** scope for application deployments.

---

## Integrating Secrets into Application Deployments

Once decrypted by the in-cluster controller, the resulting Kubernetes `Secret` has the identical name as the `SealedSecret` metadata name.

### Method A: Bulk Injection via `envFrom` (Preferred)

Exposes every key defined in the secret as an individual environment variable inside the container:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: example-app
  namespace: default
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: app
        image: ghcr.io/zipleix/example-app:latest
        envFrom:
        - secretRef:
            name: example-app-secrets
```

### Method B: Selective Key Injection via `valueFrom`

Selects and maps specific keys to explicit container environment variable names:

```yaml
spec:
  containers:
  - name: app
    image: ghcr.io/zipleix/example-app:latest
    env:
    - name: DATABASE_URL
      valueFrom:
        secretKeyRef:
          name: example-app-secrets
          key: POSTGRES_URL
```

---

## Verification & Recovery Diagnostics

### 1. Verify Unsealed Secret Creation
Check that the target `Secret` was generated by the controller:

```bash
kubectl get secret example-app-secrets -n default
```

Expected output:
```text
NAME                  TYPE     DATA   AGE
example-app-secrets   Opaque   3      45s
```

### 2. Inspect Controller Synchronization Logs
If the native secret does not appear, inspect the controller logs for decryption errors:

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets --tail=50
```

### 3. Check SealedSecret Status Conditions
View error details directly on the custom resource:

```bash
kubectl describe sealedsecret example-app-secrets -n default
```
Look for `Status.Conditions`:
* **Status: True / Type: Synced:** The secret was successfully unsealed.
* **Status: False / Type: Error:** Indicates a scope mismatch (wrong namespace/name) or that the cluster's master key has been rotated.
