# Kine Configuration

Kine is a lightweight etcd replacement that can use various backends for storage. This setup uses SQLite for simplicity and reduced resource usage compared to etcd.

## What is Kine?

Kine provides the etcd API interface while supporting multiple backends:
- **SQLite** (used here) - Embedded database, minimal overhead
- PostgreSQL - For production multi-node setups
- MySQL/MariaDB - Alternative SQL backend

## Setup

### 1. Install Kine Binary

The `04-init-control-plane.sh` script automatically installs kine v0.13.9 if not already present.

To manually install:
```bash
KINE_VERSION="v0.13.9"
curl -sfL https://github.com/k3s-io/kine/releases/download/${KINE_VERSION}/kine-${KINE_VERSION}-linux-amd64.tar.gz | tar -xz -C /usr/local/bin/
chmod +x /usr/local/bin/kine
```

### 2. Set Up as Systemd Service

For persistent operation, install the systemd service:

```bash
sudo cp manifests/kine/kine.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kine.service
sudo systemctl start kine.service
```

Then modify `04-init-control-plane.sh` to skip the kine startup block (since systemd will handle it).

**OR** - Use the quick setup (current script):

The script starts kine in the foreground during kubeadm initialization. For permanent operation, convert to systemd as shown above.

### 3. Storage Location

Kine stores data in:
```
/var/lib/kine/db.sqlite
```

Backup this file to preserve your cluster state.

## API Endpoint

Kine exposes the etcd API on:
```
http://127.0.0.1:2379
```

This is what kubeadm connects to for cluster state.

## Monitoring

Check kine status:
```bash
# If running as systemd service
sudo systemctl status kine.service

# View logs
sudo journalctl -u kine.service -f

# Check SQLite database directly
sudo sqlite3 /var/lib/kine/db.sqlite ".tables"
```

## Troubleshooting

**Port 2379 already in use:**
```bash
sudo netstat -tlnp | grep 2379
sudo systemctl stop kine.service
```

**Database corruption:**
```bash
sudo rm /var/lib/kine/db.sqlite
sudo systemctl restart kine.service
```

**Kine won't start:**
- Check permissions on `/var/lib/kine` (should be root-owned)
- Verify sqlite3 is installed: `apt-get install sqlite3`
- Check logs: `sudo journalctl -u kine.service`

## Migration from etcd

This cluster was created with local etcd configured in kubeadm. The switch to kine:
- Uses the same etcd API interface (transparent to Kubernetes)
- Uses SQLite for storage instead of etcd's embedded database
- Significantly reduces resource usage (memory and CPU)
- Eliminates etcd clustering complexity for single-node control planes

For multi-node control planes, consider using PostgreSQL backend with kine for better performance.

## References

- [Kine GitHub](https://github.com/k3s-io/kine)
- [Kine Documentation](https://github.com/k3s-io/kine/tree/master/docs)
