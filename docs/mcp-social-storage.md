# mcp-social storage

`mcp-social` is the only app that keeps persistent state inside the cluster. It
stores a SQLite database on a PersistentVolumeClaim, which is an explicit
exception to the "storage outside the cluster" rule (ADR 0002).

## What is stored

| Item | Value |
|---|---|
| PVC | `mcp/mcp-social-data` |
| Access mode | `ReadWriteOnce` |
| Default size | `1Gi` |
| Mount path | `/data` |
| Database file | `/data/social.db` (SQLite, set via `SOCIAL_DB_URL`) |

The deployment ships with `replicas: 0` (sleep pattern, ADR 0001); the PVC
survives independently of the pod, so data persists across wake/sleep cycles
and pod restarts. It does **not** survive PVC deletion or full VPS loss.

## Durability caveats

- The PVC uses the cluster default StorageClass (k3s `local-path` on the VPS),
  which is **node-local**. There is no replication and no automatic backup.
- Validate the StorageClass and put a backup routine in place **before** treating
  `mcp-social` as durable production data.
- SQLite is single-writer; take backups with `.backup`/`VACUUM INTO` (consistent
  snapshot) rather than copying `social.db` while the app is writing.

## Retention

There is no automatic pruning of the SQLite database — rows live until the
application deletes them. Capacity is bounded only by the 1Gi PVC. Monitor usage
and resize (see below) before it fills.

## Backup

### Offline backup (preferred — fits the sleep pattern)

When `mcp-social` is asleep (`replicas: 0`) the database file is idle, so a
plain copy is consistent. Mount the PVC in a throwaway pod and copy it out:

```bash
# 1. Ensure mcp-social is scaled to 0
kubectl scale deployment/mcp-social -n mcp --replicas=0

# 2. Start a temporary pod that mounts the same PVC
kubectl run social-backup -n mcp --restart=Never --image=busybox:1.36 \
  --overrides='{"spec":{"containers":[{"name":"social-backup","image":"busybox:1.36","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"mcp-social-data"}}]}}'
kubectl wait --for=condition=Ready pod/social-backup -n mcp --timeout=60s

# 3. Copy the database out
kubectl cp mcp/social-backup:/data/social.db "social.db.$(date +%Y%m%d-%H%M%S).bak"

# 4. Clean up
kubectl delete pod/social-backup -n mcp
```

### Hot backup (app awake)

If the service is running and the upstream image ships the `sqlite3` CLI, take a
consistent online snapshot without stopping it:

```bash
POD=$(kubectl get pod -n mcp -l app=mcp-social -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n mcp "$POD" -- sqlite3 /data/social.db ".backup '/data/social.bak.db'"
kubectl cp "mcp/$POD:/data/social.bak.db" "social.db.$(date +%Y%m%d-%H%M%S).bak"
kubectl exec -n mcp "$POD" -- rm -f /data/social.bak.db
```

Store backups outside the VPS (e.g. encrypted object storage). They contain
real application data — handle them as sensitive.

## Restore

Restore the file back onto the PVC while `mcp-social` is asleep, then wake it:

```bash
kubectl scale deployment/mcp-social -n mcp --replicas=0
kubectl run social-restore -n mcp --restart=Never --image=busybox:1.36 \
  --overrides='{"spec":{"containers":[{"name":"social-restore","image":"busybox:1.36","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"mcp-social-data"}}]}}'
kubectl wait --for=condition=Ready pod/social-restore -n mcp --timeout=60s
kubectl cp ./social.db.<timestamp>.bak mcp/social-restore:/data/social.db
kubectl delete pod/social-restore -n mcp
just wake-social   # or: kubectl scale deployment/mcp-social -n mcp --replicas=1
```

## Resize

`local-path` PVCs are not expandable in place. To grow capacity:

1. Edit `storage` in `k8s/base/apps/mcp-social/pvc.yaml`.
2. Take an offline backup (above).
3. Delete and re-create the PVC, then restore the backup into the new volume.

See also `docs/loki-storage.md` for the monitoring/Loki PVC and
`docs/disaster-recovery.md` for the overall recovery flow.
