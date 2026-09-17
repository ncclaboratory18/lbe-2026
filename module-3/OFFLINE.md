# Load Balancer Demo — Offline Docker Setup (4 VMs, 1 Public IP)

## Why this guide exists

Normally you'd install Docker on every VM the easy way — the online method in
[`INSTALL.md`](https://raw.githubusercontent.com/ncclaboratory18/lbe-2026/refs/heads/main/module-3/breakout-lb-demo/INSTALL.md),
using `install-docker.sh`, which needs internet access on that VM.

For this event, our shared resource group only allows **2 public IP
addresses**. The load balancer takes one. That leaves exactly **one VM**
with a public IP — call it the **master VM**. The other three VMs sit in
the same VNet/subnet with no internet access at all.

![offline-deployment](./img/topology.png)

So the plan is:

1. **`budi`** (master) has internet → we use it to download everything
   needed: the repo, the Docker `.deb` packages, and the built image.
2. **`budi`** has no direct route from your laptop to `aji`/`andi`/`etc.`
   — but `budi` itself *can* reach them, because they're all in the same
   VNet. So `budi` becomes your jump box for everything.
3. **All four VMs, including `budi`, install Docker the same way**: from
   `.deb` files, offline (`dpkg -i`), for consistency. `budi` downloads
   the `.deb`s (it has internet), then installs from them locally exactly
   like the other three do — nobody uses the online `install-docker.sh`
   path, so all 4 VMs go through an identical set of commands.
4. The image gets built once on `budi` (it's the only VM that can reach
   the internet to pull base layers), saved to a `.tar` file, and copied
   to the other three with `scp`, then loaded there — so nobody else needs
   to `docker build`. `budi` then loads and runs from that same `.tar`
   too, rather than the freshly-built image directly, so its runtime setup
   matches the other three step-for-step.
5. Every VM runs the container with its own hostname baked in via
   `-e VM_HOSTNAME=$(whoami)`, exactly like the normal INSTALL.md flow —
   so the demo still shows "who answered this request" correctly.

You will run every command yourself, one at a time, so you understand what
each one is doing. Nothing here is a script you just execute blindly.

---

## Before you start

You need, from whoever set up the VMs:

- SSH access to `budi` (the master VM), e.g. `ssh <user>@<budi_public_ip>`
- The **private IP addresses** (not public — they don't have one) of
  `aji`, `andi`, and `etc.` inside the VNet. Ask your instructor, or once
  you're on `budi` you can often find them from the Azure Portal's VM
  overview page, or by checking `/etc/hosts` if it was pre-populated.
- The same SSH key or credentials should work for all 4 VMs, since they
  were provisioned together for this event — confirm with your instructor
  if unsure.

Throughout this guide:
- `<budi_public_ip>` = the one public IP you were given
- `<username>` = your VM login username (same across all 4 VMs)
- `<aji_ip>`, `<andi_ip>`, `<etc_ip>` = private IPs of the other 3 VMs

---

## Part 1 — Get the repo onto the master VM (`budi`)

### 1.1 SSH into budi

From your laptop:

```bash
ssh <username>@<budi_public_ip>
```

You're now on `budi`. Everything in Parts 1–3 happens here.

### 1.2 Clone the repo

```bash
git clone https://github.com/ncclaboratory18/lbe-2026.git
cd lbe-2026/module-3/breakout-lb-demo
```

We will **not** use `install-docker.sh` here, even though `budi` has
internet and could. To keep every VM's setup identical and easy to reason
about, all four VMs — `budi` included — install Docker from `.deb` files
offline. `budi`'s job is to download those `.deb`s for everyone, since
it's the only VM that can reach the internet.

---

## Part 2 — Download Docker's offline installer files (on budi)

You'll now prepare the `.deb` packages that all four VMs need —
including `budi` itself.

### 2.1 Add Docker's official APT repository (if not already present)

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
```

### 2.2 Download the .deb packages (don't install — just download)

```bash
mkdir -p ~/docker-offline-debs
sudo apt-get clean
sudo apt-get install -y --download-only \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
cp /var/cache/apt/archives/*.deb ~/docker-offline-debs/
```

Check what you got:

```bash
ls ~/docker-offline-debs
```

You should see around 6–8 `.deb` files, including `docker-ce`,
`docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`,
`docker-compose-plugin`, and small dependencies like `pigz`.

`--download-only` guarantees apt resolves and downloads the *complete*
dependency tree for you — no need to hunt down each dependency by hand.

### 2.3 Install Docker on budi itself, from these same .deb files

This is the step that keeps `budi` consistent with the other three — even
though `budi` has internet, we install from the local `.deb`s, not from
apt directly:

```bash
cd ~/docker-offline-debs
sudo dpkg -i *.deb
sudo systemctl enable --now docker
```

Fix permissions if needed:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

Confirm Docker is working:

```bash
docker version
```

---

## Part 3 — Build and save the image (on budi)

`budi` is the only VM that can reach the internet to pull base image
layers, so it's the only one that runs `docker build`.

### 3.1 Build the image

```bash
cd ~/lbe-2026/module-3/breakout-lb-demo
docker build -t breakout-lb-demo .
```

### 3.2 Save the image to a file

Even though `budi` has the freshly-built image sitting in its local
Docker already, we still save it to a `.tar` and load it back in the next
step — so `budi`'s run command is identical to what `aji`/`andi`/`etc.`
will do, instead of being a special case:

```bash
docker save breakout-lb-demo -o ~/breakout-lb-demo.tar
ls -lh ~/breakout-lb-demo.tar
```

This `.tar` file contains the complete image, ready to be loaded on any
Docker host with `docker load` — including `budi` itself.

---

## Part 4 — Copy the .deb files and image to the other 3 VMs

Still on `budi`, `scp` the `.deb` files and the saved image to each of
`aji`, `andi`, and `etc.` in turn. Repeat this whole block 3 times,
substituting the right IP each time.

### 4.1 Copy to aji

```bash
ssh <username>@<aji_ip> "mkdir -p ~/docker-offline-debs"
scp ~/docker-offline-debs/*.deb <username>@<aji_ip>:~/docker-offline-debs/
scp ~/breakout-lb-demo.tar <username>@<aji_ip>:~/
```

### 4.2 Copy to andi

```bash
ssh <username>@<andi_ip> "mkdir -p ~/docker-offline-debs"
scp ~/docker-offline-debs/*.deb <username>@<andi_ip>:~/docker-offline-debs/
scp ~/breakout-lb-demo.tar <username>@<andi_ip>:~/
```

### 4.3 Copy to etc

```bash
ssh <username>@<etc_ip> "mkdir -p ~/docker-offline-debs"
scp ~/docker-offline-debs/*.deb <username>@<etc_ip>:~/docker-offline-debs/
scp ~/breakout-lb-demo.tar <username>@<etc_ip>:~/
```

> Because `aji`, `andi`, and `etc.` have no public IP, this `scp` only
> works *from `budi`*, since `budi` is on the same VNet/subnet as them.
> You cannot `scp` directly from your laptop to these three — your laptop
> can only reach `budi`.

---

## Part 5 — Install Docker offline on each of the 3 VMs

Repeat this entire part on `aji`, `andi`, and `etc.` — one VM at a time.
This is the exact same sequence you already ran on `budi` in step 2.3.
You can either SSH to each directly from your laptop if your network
allows routing into the VNet, or (more likely) SSH into `budi` first and
then SSH onward from there:

```bash
ssh <username>@<budi_public_ip>
ssh <username>@<aji_ip>
```

### 5.1 Install Docker from the local .deb files

Once you're on `aji` (or `andi`, or `etc.`):

```bash
cd ~/docker-offline-debs
sudo dpkg -i *.deb
```

If `dpkg` complains about missing dependencies, it means a package was
missed in step 2.2 — since this VM has no internet, `apt-get install -f`
won't be able to fix it automatically. Go back to `budi`, check
`ls ~/docker-offline-debs`, and re-copy anything missing.

### 5.2 Start the Docker service

```bash
sudo systemctl enable --now docker
```

### 5.3 Fix permissions if needed

```bash
sudo usermod -aG docker $USER
newgrp docker
```

### 5.4 Verify Docker is installed

```bash
docker version
```

---

## Part 6 — Load and run the image on every VM (budi, aji, andi, etc.)

This part is now identical across **all four VMs**, `budi` included —
that's the whole point of routing `budi` through the same `.tar`
load-and-run flow instead of leaving it on the image it built directly in
step 3.1.

Run this on `budi` first, then repeat it on `aji`, `andi`, and `etc.`.

### 6.1 Load the image from the tar file

```bash
docker load -i ~/breakout-lb-demo.tar
```

Confirm it's there:

```bash
docker images
```

You should see `breakout-lb-demo` listed.

### 6.2 Run the container

`$(whoami)` picks up *this* VM's own hostname automatically, so this
exact same command is correct on every VM:

```bash
docker run -d --name breakout -p 8080:8080 -e VM_HOSTNAME=$(whoami) breakout-lb-demo
```

### 6.3 Check the logs

```bash
docker logs breakout
```

Confirm the hostname shown matches the VM you're on, e.g. on `aji`:

```
Starting Breakout LB demo, hostname injected as: aji
```

### 6.4 Open port 8080 on this VM's NSG

In the Azure Portal, go to this VM's Networking page and add an inbound
rule allowing TCP port 8080, if it isn't already open. For `aji`/`andi`/
`etc.`, this only needs to allow traffic from within the VNet (or "Any",
if that's how your NSGs are already configured for this class) — they
have no public IP for the outside world to reach anyway.

### 6.5 Verify

- **On `budi`**, which has a public IP, verify from your own laptop:

  ```bash
  curl -s http://<budi_public_ip>:8080/ | head -5
  ```

- **On `aji`/`andi`/`etc.`**, which have no public IP, verify from
  `budi` instead, since it's on the same VNet:

  ```bash
  curl -s http://<aji_ip>:8080/ | head -5
  ```

Either way, you should get HTML back with that VM's hostname in it.

---

## Part 7 — Repeat Parts 5 and 6 for the remaining VMs

Once `aji` is confirmed working, repeat Parts 5 and 6 exactly the same
way for `andi`, then `etc.`. By the end, all four VMs (`budi`, `aji`,
`andi`, `etc.`) should each be running the container from the same
`.tar`-loaded image and each report their own distinct hostname when
curled.

---

## Part 8 — Set up the load balancer

This part is identical to the normal flow in `INSTALL.md`:

- **Backend pool:** add all 4 VMs (`budi`, `aji`, `andi`, `etc.`) — note
  that only `budi` has a public IP, but the load balancer talks to
  backends over their *private* IPs anyway, so this works fine for all 4.
- **Health probe:** HTTP, port 8080, path `/`.
- **Load balancing rule:** frontend port 8080 → backend port 8080,
  session persistence set to **None**.

## Part 9 — Prove it's load balancing

Point your browser at the load balancer's public IP on port 8080 and
refresh repeatedly:

```
http://<load_balancer_public_ip>:8080
```

Or you can do a curl loop from your local computer to the load balancer's public IP:

```bash
   for i in $(seq 1 10); do
     curl -s http://<load_balancer_public_ip>/config.js
     echo ""
   done
```

The hostname shown on screen should rotate between `budi`, `aji`,
`andi`, and `etc.` as the load balancer distributes requests — even
though 3 of those 4 machines have never had a public IP or direct
internet access at any point in this setup.

---

## Troubleshooting quick reference

| Problem | Likely cause / fix |
|---|---|
| `dpkg -i *.deb` fails with dependency errors | A `.deb` was missed in step 2.2 or not copied in Part 4 — re-check `ls ~/docker-offline-debs` on both `budi` and the target VM |
| `permission denied ... docker.sock` | Run `sudo usermod -aG docker $USER && newgrp docker` on that VM |
| `curl` from your laptop to `aji`/`andi`/`etc.` hangs or fails | Expected — they have no public IP. Curl from `budi` instead |
| Hostname shown is `unknown` | `$(whoami)` didn't resolve in that shell — run plain `hostname` on its own first to confirm it returns something |
| `scp` to `aji`/`andi`/`etc.` fails from your laptop | Expected — only `budi` is reachable from outside the VNet. Always `scp`/`ssh` to these three *from budi* |