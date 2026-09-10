# StatefulSet Manifest Template (Database Workloads)

## Overview

This document provides the standardized, production-ready Kubernetes manifest template for stateful workloads requiring persistent local block storage, predictable network identity, and isolated cluster networking.

Typical use cases include relational databases (PostgreSQL, MariaDB, MySQL) and persistent key-value or cache stores.

The template defines two fundamental primitives:

1. **`StatefulSet`**: Manages the deployment and scaling of a set of Pods, providing guarantees about the ordering and uniqueness of these Pods, and dynamically claims persistent disk storage via `volumeClaimTemplates`.
2. **`Service` (ClusterIP)**: Exposes the database solely within the private cluster network using stable CoreDNS resolution.

---

## Production Template: `k8s/database.yaml`

Replace all placeholder values (`DB_NAME`, `DB_IMAGE`, `DB_PORT`, `STORAGE_CAPACITY`, `DATA_MOUNT_PATH`) with the target database parameters before committing.

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: DB_NAME
  namespace: default
  labels:
    app: DB_NAME
spec:
  serviceName: DB_NAME-svc
  replicas: 1
  selector:
    matchLabels:
      app: DB_NAME
  template:
    metadata:
      labels:
        app: DB_NAME
    spec:
      containers:
      - name: database
        image: DB_IMAGE # e.g., postgres:17-alpine, mariadb:11-jammy
        imagePullPolicy: IfNotPresent
        ports:
        - name: db-port
          containerPort: DB_PORT
        envFrom:
        - secretRef:
            name: DB_NAME-secrets
        volumeMounts:
        - name: data
          mountPath: DATA_MOUNT_PATH # e.g., /var/lib/postgresql/data or /var/lib/mysql
        resources:
          limits:
            cpu: 1000m
            memory: 1Gi
          requests:
            cpu: 100m
            memory: 256Mi
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: "local-path"
      resources:
        requests:
          storage: STORAGE_CAPACITY # e.g., 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: DB_NAME-svc
  namespace: default
  labels:
    app: DB_NAME
spec:
  type: ClusterIP
  ports:
  - name: db-port
    port: DB_PORT
    targetPort: db-port
    protocol: TCP
  selector:
    app: DB_NAME
```

---

## Technical Specifications & Invariants

### 1. Volume Claim Template (`volumeClaimTemplates`)
Unlike stateless Deployments that reference a shared `PersistentVolumeClaim` (PVC), a `StatefulSet` provisions an independent PVC for each replica:

* **Format:** `<volumeMount-name>-<statefulset-name>-<ordinal>` (e.g., `data-scrabble-postgres-0`).
* **StorageClass (`local-path`):** Binds to the local disk of the k3s host at `/var/lib/rancher/k3s/storage/`.
* **Access Mode (`ReadWriteOnce`):** Restricts read and write operations to a single node at any given time.

### 2. Mandatory Network Isolation (No Ingress Rule)
Stateful database engines **must never** define an `Ingress` resource. 

* The database is only accessible via the internal Service ClusterIP or its fully qualified internal domain:
  ```text
  DB_NAME-svc.default.svc.cluster.local:DB_PORT
  ```
* Remote administration (backups, queries, inspections) must be routed through `kubectl port-forward` or executed directly within the container using `kubectl exec`.

---

## Operational Verification Runbook

### 1. Confirm Storage Binding & Pod Status

Check that the storage claim is successfully bound and the container is running:

```bash
# Verify PersistentVolumeClaim binding
kubectl get pvc -n default -l app=DB_NAME

# Verify StatefulSet rollout
kubectl rollout status statefulset/DB_NAME -n default
```

Expected PVC output:
```text
NAME                 STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
data-DB_NAME-0       Bound    pvc-12345678-abcd-ef01-2345-6789abcdef01   10Gi       RWO            local-path     2m
```

### 2. Verify Internal Resolution

Verify that client applications can resolve and reach the service port internally:

```bash
kubectl run netshoot --rm -i --tty --image nicolaka/netshoot -n default -- \
  nc -zv DB_NAME-svc.default.svc.cluster.local DB_PORT
```

Expected output:
```text
DB_NAME-svc.default.svc.cluster.local (10.43.x.x:5432) open
```
