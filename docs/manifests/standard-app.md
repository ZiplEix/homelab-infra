# Standard Application Manifest Template

## Overview

This document provides the standardized, production-ready Kubernetes manifest template for stateless microservices (backend APIs, frontend UIs, and worker nodes) running on the k3s cluster.

It consolidates the three essential primitives into a single declarative file:

1. **`Deployment`**: Manages pod lifecycle, replicas, rollouts, and container specifications.
2. **`Service`**: Exposes the application internally within the cluster via a stable `ClusterIP`.
3. **`Ingress`**: Configures Traefik Layer 7 routing, binds the Let's Encrypt certificate managed by `cert-manager`, and synchronizes Cloudflare records via `external-dns`.

---

## Production Template: `k8s/app.yaml`

Replace all placeholder values (`APP_NAME`, `CONTAINER_PORT`, `SERVICE_PORT`, `DOMAIN_NAME`) with your application-specific parameters before applying.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: APP_NAME
  namespace: default
  labels:
    app: APP_NAME
spec:
  replicas: 1
  revisionHistoryLimit: 3
  selector:
    matchLabels:
      app: APP_NAME
  template:
    metadata:
      labels:
        app: APP_NAME
    spec:
      containers:
      - name: web
        image: ghcr.io/zipleix/APP_NAME:latest
        imagePullPolicy: Always
        ports:
        - name: http
          containerPort: CONTAINER_PORT
        env:
        - name: PORT
          value: "CONTAINER_PORT"
        - name: NODE_ENV
          value: "production"
        # Optional: Load sensitive environment variables from a SealedSecret
        # envFrom:
        # - secretRef:
        #     name: APP_NAME-secrets
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 50m
            memory: 128Mi
        readinessProbe:
          httpGet:
            path: /
            port: http
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /
            port: http
          initialDelaySeconds: 15
          periodSeconds: 20
          timeoutSeconds: 3
          failureThreshold: 3
---
apiVersion: v1
kind: Service
metadata:
  name: APP_NAME-svc
  namespace: default
  labels:
    app: APP_NAME
spec:
  type: ClusterIP
  ports:
  - name: http
    port: SERVICE_PORT
    targetPort: http
    protocol: TCP
  selector:
    app: APP_NAME
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: APP_NAME-ingress
  namespace: default
  annotations:
    # Forces routing through the secure entrypoint
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    # Enables TLS on the Traefik router
    traefik.ingress.kubernetes.io/router.tls: "true"
    # Triggers cert-manager to issue a certificate via DNS-01
    cert-manager.io/cluster-issuer: letsencrypt-prod
    # Designates the target public IP for external-dns reconciliation
    external-dns.alpha.kubernetes.io/target: 82.67.198.156
spec:
  ingressClassName: traefik
  rules:
  - host: DOMAIN_NAME.baptiste.zip
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: APP_NAME-svc
            port:
              name: http
  tls:
  - hosts:
    - DOMAIN_NAME.baptiste.zip
    secretName: DOMAIN_NAME-baptiste-zip-tls
```

---

## Configuration Parameter Reference

### Deployment Settings

| Field | Description | Recommendation |
| :--- | :--- | :--- |
| `spec.replicas` | Number of desired pod instances. | Set to `1` for homelab services. Increase if load balancing or zero-downtime rolling upgrades are required. |
| `imagePullPolicy` | Behavior when pulling images on pod start. | Set to `Always` when consuming rolling `:latest` image tags from GHCR. |
| `readinessProbe` | Controls when traffic should start routing to the pod. | Directs checks to an endpoint returning HTTP `200` (e.g. `/` or `/healthz`). |
| `livenessProbe` | Controls when Kubernetes restarts an unresponsive container. | Configure with higher delay and threshold than readiness probes to prevent crash loops under heavy load. |

### Service & Port Alignment

| Service Field | Deployment Equivalent | Purpose |
| :--- | :--- | :--- |
| `ports[].port` | N/A | Port exposed internally inside the cluster. |
| `ports[].targetPort` | `containers[].ports[].name` or `containerPort` | Port on which the application container listens. Binding via named ports (`http`) decouples service definitions from container port numbers. |
| `selector.app` | `metadata.labels.app` | Matches incoming traffic to the appropriate application pods. |

### Mandatory Ingress Annotations

* **`traefik.ingress.kubernetes.io/router.entrypoints: websecure`**: Ensures the router does not process unencrypted HTTP traffic.
* **`traefik.ingress.kubernetes.io/router.tls: "true"`**: Activates TLS termination within the Traefik routing layer.
* **`cert-manager.io/cluster-issuer: letsencrypt-prod`**: Directly instructs `cert-manager` to generate a `Certificate` resource handled by the Cloudflare DNS-01 ACME issuer.
* **`external-dns.alpha.kubernetes.io/target: 82.67.198.156`**: Overrides the internal node IP, informing `external-dns` to publish the public WAN address to Cloudflare DNS.

---

## Pre-Flight Checklist Before Applying

1. [ ] The container image is publicly accessible on GHCR (`ghcr.io/zipleix/APP_NAME:latest`).
2. [ ] The pre-existing DNS record on Cloudflare (if any) has been removed or switched to **DNS Only (Grey Cloud)**.
3. [ ] All placeholders (`APP_NAME`, `CONTAINER_PORT`, `SERVICE_PORT`, `DOMAIN_NAME`) have been replaced consistently across Deployment, Service, and Ingress sections.
4. [ ] If using secrets, the corresponding `SealedSecret` has been created and verified in the target namespace.
