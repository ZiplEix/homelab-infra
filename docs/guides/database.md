# Base de données & Stockage Persistant

Pour déployer une base de données avec rétention de données (PostgreSQL, MariaDB, Redis), on utilise un **StatefulSet** associé à un **PersistentVolumeClaim** utilisant le storage provisioner `local-path` de k3s.

## Règles de Sécurité
* **Aucun Ingress public :** Une base de données ne doit **JAMAIS** avoir d'Ingress Traefik.
* **DNS interne :** Les applications accèdent à la base via l'adresse de service interne :
  ```text
  scrabble-postgres-svc.default.svc.cluster.local:5432
  ```

## Dump & Restauration
Pour migrer ou sauvegarder les données depuis ou vers le cluster :

```bash
# Dump depuis un Postgres externe vers un fichier local :
pg_dump -h IP_SOURCE -p 5432 -U postgres -d nom_base -F c -b -v -f /tmp/backup.dump

# Restauration dans le pod k3s :
kubectl exec -i scrabble-postgres-0 -n default -- pg_restore -U postgres -d nom_base -v < /tmp/backup.dump

# Connexion interactive psql au conteneur :
kubectl exec -it scrabble-postgres-0 -n default -- psql -U postgres -d nom_base
```
