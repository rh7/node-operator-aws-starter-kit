# Example idOS node with Transit Gateway (TGW)

This example connects your VPC to the idOS network using **AWS Transit Gateway**. After idOS approves your account and you apply this Terraform config, your node can reach all other idOS VPCs over private IPs in the `10.x.x.x` range.

**This setup uses TGW only** — there is no VPC peering.

---

## Why Transit Gateway (and not VPC peering)?

- **One connection for all idOS VPCs:** Attach once to the idOS Transit Gateway; you reach every other attached idOS VPC without separate peering to each.
- **Simpler operations:** idOS manages the TGW and RAM share; you accept the share, attach your VPC, and add one route (`10.0.0.0/8` → TGW).
- **Easier scaling:** New participants join via the same TGW; no new peering connections to create or accept.

---

## Prerequisites

- AWS account in **eu-central-1** (same region as the idOS Transit Gateway).
- Terraform >= 1.0.
- **VPC CIDR assigned by idOS** (must not overlap existing participants; see [CIDR allocation](#cidr-allocation-reference) below).
- Access to the `idos-kgw` repository and node files (`genesis.json`, `config.toml`) from idOS.

---

## Playbook

### Step 1: Request access from idOS

Send the following to idOS:

| What to provide     | Example / format |
|---------------------|------------------|
| **AWS account ID**   | `123456789012` |
| **Requested VPC CIDR** | e.g. `10.1.0.0/16` or `10.4.0.0/16` (idOS will confirm or assign) |
| **AWS region**       | Must be `eu-central-1` |
| **Contact**          | Email or channel for receiving the share details |

### Step 2: idOS approves and sends you TGW details

idOS will:

1. Reserve your CIDR and add your **AWS account ID** to the TGW RAM share.
2. Send you:
   - **Transit Gateway ID** (e.g. `tgw-036bcb1e0b9289314`)
   - **RAM resource share ARN** (e.g. `arn:aws:ram:eu-central-1:XXXXXXXXXXXX:resource-share/...`)
   - **Confirmed VPC CIDR** (e.g. `10.1.0.0/16`)
   - **Node files:** `genesis.json` and `config.toml`

### Step 3: Deploy this Terraform config

1. **Generate an SSH key pair** (for the example instance):

   ```bash
   ssh-keygen -f id_example
   ```

2. **Create `terraform.tfvars`** (e.g. from the example):

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

   Fill in the values idOS sent you:

   ```hcl
   region             = "eu-central-1"
   name               = "Example"
   transit_gateway_id  = "tgw-xxxxxxxxx"        # From idOS
   tgw_ram_share_arn  = "arn:aws:ram:..."     # From idOS
   vpc_cidr           = "10.1.0.0/16"         # Confirmed by idOS
   ssh_keypair_pub_path = "id_example.pub"
   ```

3. **Apply** (Terraform will accept the RAM invitation and create the TGW attachment):

   ```bash
   terraform init
   terraform plan   # Should show: accepter + TGW attachment + route
   terraform apply
   ```

   Terraform accepts the RAM share when you apply. If you see **"No pending RAM Resource Share invitation found"**, the share was already accepted (e.g. in the console)—see [Troubleshooting](#troubleshooting) to import it.

### Step 4: Verify connectivity (TGW)

From your instance, test reachability to another idOS participant (idOS can give you a private IP to test):

```bash
ssh -i id_example ec2-user@$(terraform output -raw instance_public_ip)
ping -c 3 10.0.1.50
nc -zv 10.0.1.50 8484
```

### Step 5: Configure the VM to run the node

1. **Connect to the VM**

   ```bash
   ssh -i id_example ec2-user@$(terraform output -raw instance_public_ip)
   ```

2. **Install Docker and log out** (so the `docker` group is applied)

   ```bash
   sudo dnf install -y docker
   sudo usermod -a -G docker ec2-user
   sudo systemctl enable --now docker.service
   exit
   ```

3. **Reconnect with SSH agent forwarding** (for GitHub)

   ```bash
   ssh -A -i id_example ec2-user@$(terraform output -raw instance_public_ip)
   ```

4. **Install tools**

   ```bash
   sudo dnf install -y git git-lfs jq vim
   sudo curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
   sudo chmod 755 /usr/local/bin/docker-compose
   ssh-keyscan github.com >> .ssh/known_hosts
   ```

5. **Clone idos-kgw**

   ```bash
   git clone git@github.com:idos-network/idos-kgw.git
   cd idos-kgw
   git lfs pull
   ```

6. **Create initial configuration**

   `.env` and `compose.yaml` are not in the repository. Create both. `ENVIRONMENT` must be the
   `environment` value from your `terraform.tfvars` (default `partner`): it selects the
   CloudWatch log group this Terraform creates (on your machine, `terraform output log_group_name`).

   ```bash
   ENVIRONMENT=partner   # your Terraform "environment" value
   ln -s compose.prod.yaml compose.yaml
   cat > .env <<EOF
   ARCH=amd64
   KWILD_LOG_LEVEL=info
   ENVIRONMENT=$ENVIRONMENT
   AWS_REGION=eu-central-1
   EOF
   docker network create kwil-dev
   docker-compose run --build --rm kwild ./kwild key gen --key-file /app/home_dir/nodekey.json
   exit
   ```

7. **Copy `genesis.json` and `config.toml`** (from idOS) into the node home dir on the VM

   `/data/kwild-home_dir` is owned by root (Docker created it in the previous step), so copy
   the files to the home directory first and move them with `sudo`:

   ```bash
   scp -i id_example genesis.json config.toml ec2-user@$(terraform output -raw instance_public_ip):
   ssh -i id_example ec2-user@$(terraform output -raw instance_public_ip) 'sudo mv genesis.json config.toml /data/kwild-home_dir/'
   ```

### Step 6: Run the node

1. **Connect to the VM** (same as Step 5.1)

2. **Start the node**

   ```bash
   cd idos-kgw
   docker-compose -f compose.prod.yaml up -d --build --force-recreate
   ```

3. **Wait until the node catches up** (may take a few hour)

   ```bash
   docker-compose logs -f
   ```

   Look for logs like `"msg":"finalizing commit of block"`. Report any obvious crashes to idOS.

4. **Exit when done**

   ```bash
   exit
   ```

### Step 7: Make the node a validator (optional)

1. **Connect to the VM** (same as Step 5.1)

2. **Request to become a validator**

   ```bash
   cd idos-kgw
   docker-compose -f compose.prod.yaml run --rm kwild kwild validators join -s /sockets/kwild.socket
   ```

3. **Ask idOS to approve** your validator request.

4. **Check status**

   - Get the node’s validator public key (the `grep` drops the `idos-kwild app version` line
     that current builds print on stdout before the JSON):

     ```bash
     docker-compose -f compose.prod.yaml run --rm kwild kwild admin status --rpcserver /sockets/kwild.socket | grep -v '^idos-kwild app version' | jq -r .validator.pubkey
     ```

   - See if that key is in the validators list:

     ```bash
     docker-compose -f compose.prod.yaml run --rm kwild kwild validators list -s /sockets/kwild.socket
     ```

### Step 8: Provide private IP to idOS (load balancer)

Send your instance **private IP** to idOS so they can add it to their load balancer:

```bash
terraform output -raw instance_private_ip
```

---

## What this Terraform creates

| Resource           | Purpose |
|--------------------|---------|
| VPC                | Your network with the idOS-assigned CIDR |
| Subnets            | One per AZ (for TGW attachment and instance) |
| Internet gateway   | Public access (SSH to instance) |
| Route table        | `0.0.0.0/0` → IGW; `10.0.0.0/8` → Transit Gateway |
| RAM accepter       | Accepts the TGW resource share from idOS (one-time) |
| TGW VPC attachment | Connects your VPC to the idOS Transit Gateway |
| Security group     | SSH from internet; Kwil RPC (8484) and P2P (6600) from `10.0.0.0/8` |
| EC2 instance       | Example node (Amazon Linux 2023, t3.large) |
| CloudWatch log group | `/ec2/<environment>-idos-kwil-node/containers` for the `awslogs` driver in `compose.prod.yaml`, plus write access for the instance role |

---

## CIDR allocation (reference)

| CIDR           | Participant   |
|----------------|---------------|
| 10.0.0.0/16    | idOS          |
| 10.1.0.0/16    | Partner1      |
| 10.2.0.0/16    | Partner2      |
| 10.3.0.0/16    | Partner3      |
| 10.4.0.0/16    | Available     |
| …              | Ask idOS for assignment |

Specific allocations are confirmed by idOS.

---

## Troubleshooting

- **"No pending RAM Resource Share invitation found"**
  The share was already accepted (e.g. in the console). Import it so Terraform manages the existing acceptance:
  `terraform import aws_ram_resource_share_accepter.tgw "<your_tgw_ram_share_arn>"`
  Use the exact RAM share ARN idOS gave you (e.g. `arn:aws:ram:eu-central-1:XXXXXXXXXXXX:resource-share/...`).

- **"ResourceAlreadyExistsException" for the CloudWatch log group**
  The group was created outside Terraform (e.g. by hand for an existing node). Import it:
  `terraform import aws_cloudwatch_log_group.node "/ec2/<environment>-idos-kwil-node/containers"`

- **TGW attachment stuck in "pending"**
  Accept the RAM share first (Resource Access Manager → Shared with me). Ensure subnets are in `eu-central-1`.

- **Routes not working**
  Confirm the TGW attachment is in `available` state. Check the route table has `10.0.0.0/8` → TGW. Verify the instance’s security group allows 8484/6600 from `10.0.0.0/8`.

- **Connectivity test**
  From your instance: `ping 10.0.x.x`, `nc -zv 10.0.x.x 8484` (use an IP idOS provides).

---

## Support

For TGW access or issues, contact idOS with your AWS account ID and the details from Step 1.
