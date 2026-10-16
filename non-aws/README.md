# Running an idOS node outside AWS

This directory runs the same node as the main guide (`idos-kgw`'s `compose.prod.yaml`) on an
Ubuntu 24.04 server outside AWS, e.g. Hetzner Cloud or Contabo, behind the provider's firewall.
Three things in the AWS setup are AWS-specific:

| AWS setup | Here |
|---|---|
| Private `10.x` connectivity through the idOS Transit Gateway | P2P on `6600/tcp` over the internet, restricted by the provider firewall (needs idOS, see [Join an idOS network](#3b-join-an-idos-network)) |
| `awslogs` logging driver (CloudWatch) | `compose.portable.yaml`: Docker `local` driver with rotation |
| Admin socket in `/home/ec2-user/sockets` | `/data/sockets` |

`compose.portable.yaml` is an override file; it changes nothing else in `compose.prod.yaml`.

## 1. Host

Ubuntu 24.04 on x86_64, with at least the resources of the AWS example (t3.large: 2 vCPU, 8 GB
RAM). Disk use grows with the chain; ask idOS for the current size of the network you join.

Use `cloud-init.yaml` as the server's user data after putting your SSH public key in it. It
installs Docker CE with the Compose plugin, git-lfs and ufw, creates the `idos` user, and creates
`/data/kwild-home_dir`, `/data/sockets` and `/data/postgres-data`.

In the provider firewall, allow `22/tcp` from your own addresses. Open `6600/tcp` only to idOS
node addresses, and only when peers must connect to your node. Ports published by Docker bypass
ufw, so the provider firewall is the control for `6600`.

## 2. Build

`idos-kgw` is a private repository: clone it with a read-only deploy key or SSH agent forwarding.

```bash
git clone git@github.com:idos-network/idos-kgw.git && cd idos-kgw
git lfs pull   # kwil-cli archives that the Dockerfile copies
cp /path/to/node-operator-aws-starter-kit/non-aws/compose.portable.yaml .
cat > .env <<'EOF'
ARCH=amd64
KWILD_LOG_LEVEL=info
# Interpolated by the awslogs block in compose.prod.yaml; the override replaces that block.
ENVIRONMENT=portable
AWS_REGION=none
# 0.0.0.0 once peers must connect to this node; loopback keeps 6600 closed.
P2P_HOST_IP=127.0.0.1
EOF
dc() { docker compose -f compose.prod.yaml -f compose.portable.yaml "$@"; }
dc build
dc run --rm kwild kwild key gen --key-file /app/home_dir/nodekey.json
dc run --rm kwild kwild key info --key-file /app/home_dir/nodekey.json   # the Node ID to give idOS
```

## 3a. Standalone test network

A single-validator chain of your own, to try the build and the operations without idOS.

```bash
PUB='<"Public key (plain hex)" from key info>'
dc run --rm kwild kwild setup genesis --out /app/home_dir/ --chain-id idos-test \
  --validator "$PUB#secp256k1:1" --leader "$PUB#secp256k1" --max-block-size 10485760
dc run --rm kwild kwild setup init --genesis /app/home_dir/genesis.json --root /app/home_dir/node \
  --key-file /app/home_dir/nodekey.json --log.output stdout --db.host postgres \
  --rpc.max-req-size 42000000 --admin.listen /sockets/kwild.socket --max-block-size 10485760
sudo mv /data/kwild-home_dir/node/config.toml /data/kwild-home_dir/
sudo rm -rf /data/kwild-home_dir/node
dc up -d
curl -s localhost:8484/api/v1/health | jq .services.user
```

To add a follower, set up a second host the same way, copy the leader's `genesis.json` to it, and
run `setup init` with `--p2p.bootnodes "$PUB#secp256k1@<leader-ip>:6600"`. The leader then needs
`P2P_HOST_IP=0.0.0.0` and `6600/tcp` open to the follower.

## 3b. Join an idOS network

The AWS setup connects nodes over the idOS Transit Gateway, so a node outside AWS needs a P2P path
agreed with idOS. This section covers a non-validator node: validators also need the bridge RPC
and the private IPFS swarm, which are only reachable over the Transit Gateway. Ask idOS for:

1. `genesis.json` and `config.toml` for the network, and the idos-kgw tag it runs.
2. One or more bootnodes reachable from your host, as `<node-id>#secp256k1@<address>:6600`.
3. The node IDs of the statesync snapshot providers. Replaying from genesis does not work on
   idOS networks (old blocks were produced by older extension code), so the node must start
   from a snapshot.

Build from that tag (`git checkout <tag>` in `idos-kgw` before `dc build`). Put the two files in
`/data/kwild-home_dir/`, then edit `config.toml`:

- `[p2p] bootnodes` = the addresses from (2); `[p2p] external_address = ''` (the file may carry
  another node's address; a non-validator only connects out).
- `[state_sync] enable = true` and `trusted_providers` = the node IDs from (3).
- `[db] host = 'postgres'` and `[admin] listen = '/sockets/kwild.socket'`.
- Remove any `[erc20_bridge.signer]` entries: they belong to validators, and kwild refuses to
  start if a listed key file is missing.

```bash
dc up -d
dc logs -f kwild   # snapshot restore first, then "finalizing commit of block"; catch-up takes hours
dc exec kwild kwild admin status --rpcserver /sockets/kwild.socket | grep -v '^idos-kwild app version' | jq .sync
```

The `grep` drops the `idos-kwild app version` line that current builds print on stdout before the
JSON.

<!-- cspell:words Contabo bootnodes idos IPFS kwil kwild nodekey rpcserver statesync tfvars -->
