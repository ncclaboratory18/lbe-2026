# Module 3: Load Balancing with Azure

## Lab Based Education, Meeting 3

---

## 1. Overview

This module ties together everything from Meeting 1 (Azure) and Meeting 2 (Docker). Each team member has their own virtual machine running a Dockerized web app. In this session, the team will place those virtual machines behind a single Azure Load Balancer and prove that traffic is being distributed across them.

By the end of this module, each team will have a shared, working setup that becomes the foundation for their final project.

---

## 2. Learning Objectives

By the end of this session, participants will be able to:

1. Explain what a load balancer does and why it matters for availability and scaling.
2. Set up a shared Azure environment that multiple team members can work in together.
3. Configure a Network Security Group (NSG) to allow the correct traffic.
4. Create a Standard Azure Load Balancer with a backend pool, health probe, and load balancing rule.
5. Prove, with evidence, that requests are being distributed across multiple backend virtual machines.
6. Observe how the load balancer reacts when one backend instance becomes unhealthy.

---

## 3. Before You Start: Prerequisites Checklist

Every participant should confirm the following before this session begins. If any item is missing, resolve it before the session starts, since the whole module depends on it.

- [ ] Active Azure for Students subscription (Meeting 1)
- [ ] Comfortable creating a VM and connecting to it over SSH (Meeting 1)
- [ ] Docker installed and working, either locally or on their VM (Meeting 2)
- [ ] The lab provided Breakout LB Demo app files available (`Dockerfile`, `entrypoint.sh`, `nginx.conf`, `app/` folder) (Meeting 2)
- [ ] The app has been built into a Docker image and run successfully at least once, with the browser confirming it shows the correct VM hostname on screen (Meeting 2)
- [ ] Each participant knows their own VM's public IP address and SSH key location

---

## 4. Important Note on Load Balancer Type

Azure used to offer a free "Basic" Load Balancer. That SKU was retired on September 30, 2025, and can no longer be created. This guide uses the **Standard Load Balancer**, which is the only option available now.

Two things follow from this that participants must know before starting:

1. **It is not free.** It has a small hourly cost plus a data processing cost. Azure for Students credit will cover this for a short workshop session, but everyone should clean up resources afterward (see Section 13).
2. **It is closed by default.** Unlike the old Basic Load Balancer, a Standard Load Balancer and the VMs behind it will not accept any inbound traffic unless a Network Security Group explicitly allows it. Section 8 of this guide covers this step. Skipping it is the most common reason a load balancer "does not work."

---

## 5. Key Concepts (Short Version)

Keep this part brief when presenting live. Use the terms below as they come up in the hands-on steps rather than lecturing through all of them up front.

- **Load balancer**: a single entry point that receives traffic and forwards it to one of several backend servers.
- **Frontend IP**: the public IP address that clients connect to. This is the load balancer's address, not any individual VM's address.
- **Backend pool**: the group of VMs that will receive traffic from the load balancer.
- **Health probe**: a periodic check the load balancer runs against each backend VM to decide if it is healthy enough to receive traffic.
- **Load balancing rule**: the configuration that ties a frontend port to a backend port, using a specific backend pool and health probe.
- **Network Security Group (NSG)**: a firewall attached to a VM's network interface or subnet. Standard Load Balancer requires an NSG rule to allow the traffic through.

---

## 6. The App Used in This Guide: Breakout LB Demo

This module uses a purpose built demo app instead of a generic placeholder: a playable Breakout game where the wall of blocks spells out the VM's own hostname. It is a static site (HTML, CSS, JavaScript) served by nginx inside a single Docker container, no database, no backend service.

The values below are fixed for this app and used consistently through the rest of this guide.

| Item | Value |
|---|---|
| Container image name | `breakout-lb-demo` |
| Port (inside container and published on each VM's host) | `8080` |
| Load balancer's public-facing port | `80` (so participants can visit `http://<public-ip>` with no port number; the load balancer forwards internally to port 8080 on whichever VM it picks, see Section 12.5) |
| Health check path | `/` (returns HTTP 200 reliably, no login or state required) |
| Instance identifier | The VM's own hostname, spelled out in the block wall and shown as plain text above the canvas |
| How the instance identifier is set | The `VM_HOSTNAME` environment variable is passed in at `docker run` time using `$(whoami)`. The container's `entrypoint.sh` script writes it into a generated `config.js` file before nginx starts, so the same built image shows a different hostname on every VM |
| VM operating system | Ubuntu 22.04 LTS (or newer LTS available in the portal) |
| VM size | `Standard_B1s` (free tier eligible, sufficient for this app since it is a lightweight static site with no database) |
| Region | Southeast Asia, or the region closest to your location |

Because the hostname is baked in at container startup rather than at image build time, the exact same image can run unmodified on every team member's VM and still correctly identify which VM answered a request. This is what makes the load balancer proof in Section 13 straightforward: you are not guessing whether two responses came from different VMs, the app tells you directly.

---

## 7. Part 0: Team Environment Setup

This step matters because each participant likely created their own VM under their own personal Azure for Students subscription during Meetings 1 and 2. A load balancer's backend pool can only include VMs that live in the same virtual network as the load balancer itself. Three separate personal subscriptions means three separate virtual networks by default, which will not work.

Each team has two options. Pick one before continuing.

### Option A: Shared resource group under one team member's subscription (recommended)

Important: in Azure, billing always follows the subscription, not the person who created the resource. This means every VM, public IP, and load balancer created inside the Team Owner's resource group is charged against the Team Owner's own Azure for Students credit, even when a teammate is the one who clicked Create using their own login and Contributor access. Teammates do not pay individually for anything created this way.

Make sure the team is aware of this before choosing a Team Owner, and agree as a team on how to keep usage fair, for example by taking turns being the Team Owner across different modules, or by everyone agreeing to deallocate VMs promptly after each session so the shared credit lasts through the final project. If one member is not comfortable being the sole billing point for the whole team, revisit this decision before continuing.

1. As a team, choose one member to be the **Team Owner**. Their Azure subscription will host all the shared resources for this module and the final project, and their credit balance is what gets consumed.
2. The Team Owner signs in to the Azure Portal and creates a new **Resource Group** for the team, for example `rg-team01-lbe`.
   ![](img/create-resouce-group.png)
3. The Team Owner opens the new resource group, selects **Access control (IAM)** from the left menu, and selects **Add role assignment**.
   ![](img/add-role-assignment-iam.png)
4. The Team Owner assigns the **Contributor** role to each teammate, using the email address associated with their Azure for Students account.
   ![](img/add-role-assignment-select-member.png)
   ![](img/add-role-assignment-review.png)
5. Each teammate checks their email for an invitation (if the accounts are in different Azure AD tenants) and accepts it. Once accepted, they can switch to the Team Owner's directory from the Azure Portal account menu and see the shared resource group.
6. Before any teammate tries to create a VM, the **Team Owner** (not the teammate) must register the resource providers this module needs, since this requires permission at the subscription level and Contributor access on a resource group alone is not enough for it. While signed in as the Team Owner, go to **Subscriptions**, select the subscription being used, select **Settings > Resource providers**, search for `Microsoft.Compute` and `Microsoft.Storage`, and select **Register** for each if they show as unregistered. This is a one-time step per subscription.
7. From this point forward, every resource for this module (virtual network, VMs, load balancer) is created inside this one shared resource group, even though each teammate is creating their own VM using their own login.

If a teammate tries to create a VM before this step and sees an error mentioning a resource provider is not registered and they do not have permission to register it, this is expected. It means step 6 has not been completed yet by the Team Owner. It is not a sign that anything else is misconfigured.

If your organization already provides a shared class subscription or a shared Azure AD tenant for the workshop, skip steps 2 through 5 and simply confirm everyone has Contributor access to one shared resource group there instead.

### Option B: Keep separate subscriptions and use VNet peering (advanced, not recommended for this session)

It is technically possible to peer virtual networks across separate subscriptions so that a load balancer in one subscription can reach VMs in another. This adds real networking complexity (cross-tenant permissions, peering configuration, potential extra cost) that is not a good use of limited session time for a beginner audience. Only use this path if a team specifically wants the challenge, and treat it as a stretch goal, not the main path.

**For the rest of this guide, we assume Option A: one shared resource group, one shared virtual network, all resources created inside it.**

---

## 8. Part 1: Prepare the Shared Virtual Network

1. Inside the shared resource group, search for **Virtual networks** and select **Create**.
2. Configure the following on the Basics tab:
   - Resource group: the shared team resource group from Part 0
   - Name: for example `vnet-team01`
   - Region: the same region for all resources in this module

   ![](img/create-virtual-network-basics-1.png)

3. Select **Review + create**, then **Create**.

Every VM created for this module must use this same virtual network and the same subnet within it.

---

## 9. Part 2: Each Member Creates a Virtual Machine

Each teammate repeats this step individually, using their own Azure Portal session, but creating the VM inside the shared resource group and shared virtual network from Part 1.

### 9.0 Generate Your SSH Key Pair First

Do this on your own laptop, before touching the Azure Portal, not on the VM (the VM doesn't exist yet).

An SSH key pair is two files that work together: a private key, which stays on your laptop and must never be shared, and a public key, which is safe to hand to anyone, including Azure, since it can only be used to verify you, not to impersonate you. Azure can generate this pair for you automatically during VM creation, but generating it yourself first gives you a key you control, understand, and can reuse cleanly across every VM you create in this module.

1. Open a terminal (WSL, macOS Terminal, or Linux) and run:
   ```
   ssh-keygen -t ed25519 -C "team01-<your_name>" -f ~/.ssh/lbe_team01_key
   ```
   - `-t ed25519` picks a modern, fast key type. If your system is old enough that it doesn't support ed25519, use `-t rsa -b 4096` instead.
   - `-C` is just a label (a comment) attached to the key, useful for telling multiple keys apart later. Replace `<your_name>` with your own name, for example `team01-danish`.
   - `-f ~/.ssh/lbe_team01_key` sets a specific filename for this key, instead of overwriting any default key you might already have (`~/.ssh/id_ed25519`).
2. You'll be asked for a passphrase. For a short workshop session, pressing Enter twice to leave it empty is acceptable. For anything you intend to keep using afterward, set a real passphrase, since an empty passphrase means anyone who gets a copy of your private key file can use it directly.
3. This produces two files:
   - `~/.ssh/lbe_team01_key` (the private key, keep this on your laptop only)
   - `~/.ssh/lbe_team01_key.pub` (the public key, safe to paste into Azure)
4. Lock down the private key's permissions, which SSH requires to even accept using it:
   ```
   chmod 600 ~/.ssh/lbe_team01_key
   ```
5. Print the public key so you can copy it:
   ```
   cat ~/.ssh/lbe_team01_key.pub
   ```
   Copy the entire output, including the `ssh-ed25519` prefix at the start and the comment at the end. You'll paste this into the Azure Portal in the next step.

### 9.1 Create the VM

1. Search for **Virtual machines** and select **Create > Azure virtual machine**.
2. On the Basics tab:
   - Resource group: the shared team resource group
   - Virtual machine name: something identifiable per person, for example `budi` or `danish`
   - Region: same as the shared virtual network
   - Image: Ubuntu Server 22.04 LTS (or the current LTS version offered)
   - Size: `Standard_B1s` or similar free tier eligible size
   - Authentication type: SSH public key
   - Username: your choice, written down for later
   - SSH public key source: **Use existing public key**
   - SSH public key: paste the full contents you copied with `cat` in step 9.0.5
   
   ![alt text](img/create-virtual-machine-basics-1.png) ![alt text](img/create-virtual-machine-basics-2.png) ![alt text](img/create-virtual-machine-basics-3.png)
3. On the Networking tab:
   - Virtual network: select the shared `vnet-team01` created in Part 1
   - Subnet: the subnet inside that virtual network
   - Public IP: create a new one, Standard SKU
   - NIC network security group: select **None** for now, or Basic. We will configure NSG rules explicitly in Part 4 rather than relying on the default here.
   
   ![](img/create-virtual-machine-network.png)
   
4. Select **Review + create**, review the settings, then **Create**. Since you supplied your own public key, there is no private key file to download this time, you already have it on your laptop from step 9.0.
5. Once deployment finishes, note down the VM's public IP address.
6. Connect using the specific private key file you generated, not the default:
   ```
   ssh -i ~/.ssh/lbe_team01_key <username>@<your_vm_public_ip>
   ```

Repeat this for every team member. At the end of this part, the team should have 2 or 3 VMs, all inside the same resource group and the same virtual network, each with its own public IP.

---

## 10. Part 3: Verify the App Runs on Each VM

Each teammate does this on their own VM.

1. Connect over SSH, using the specific key file generated in Part 2:
   ```
   ssh -i ~/.ssh/lbe_team01_key <username>@<your_vm_public_ip>
   ```
2. Confirm Docker is installed and running:
   ```
   docker --version
   sudo systemctl status docker
   ```
3. Copy the Breakout LB Demo project folder onto this VM (`scp` from your local machine, or clone it if it lives in a repo), then build the image:
   ```
   cd breakout-lb-demo
   docker build -t breakout-lb-demo .
   ```
4. Run the container. The `-e VM_HOSTNAME=$(whoami)` part is not optional, it is what makes this specific VM show its own hostname instead of a generic placeholder:
   ```
   docker run -d --name breakout -p 8080:8080 -e VM_HOSTNAME=$(whoami) breakout-lb-demo
   ```
5. Confirm the hostname was actually picked up, before doing anything else:
   ```
   docker logs breakout
   ```
   You should see a line like `Starting Breakout LB demo, hostname injected as: danish`. If it says `unknown` instead, run a plain `whoami` command on the VM by itself first to confirm the shell substitution has something to work with.
6. From inside the SSH session, confirm the app responds locally on the VM:
   ```
   curl -s http://localhost:8080/config.js
   ```
   This should return something like `window.APP_CONFIG = { hostname: "danish" };`. This is a more useful check than curling the full HTML page, since it isolates exactly the one value that matters for proving load balancing later.
7. From your own machine's browser or terminal (not from inside the SSH session), try:
   ```
   curl http://<your_vm_public_ip>:8080/config.js
   ```
   At this point, this should fail or hang if there is no NSG rule allowing port 8080 yet. That is expected, this step only confirms the container itself is running correctly on the VM.

Checkpoint: each teammate confirms, inside their own SSH session, that `curl http://localhost:8080/config.js` returns their own VM's actual hostname, not `unknown` and not another VM's name.

---

## 11. Part 4: Configure Network Security Group Rules

This step is required because Standard Load Balancer blocks all inbound traffic by default. Without this, the health probe will always fail and the load balancer will show every backend as unhealthy.

Do this once per VM, since each VM has its own network interface.

1. Open the VM's resource page in the Azure Portal.
2. Select **Networking** from the left menu.
3. Select **Add inbound port rule**.
   
   ![](img/inbound-port.png)
   
4. Configure the rule:
   - Source: Any (or restrict later if you want to practice tightening security)
   - Source port ranges: `*`
   - Destination: Any
   - Destination port ranges: `8080`
   - Protocol: TCP
   - Action: Allow
   - Priority: any unused value, for example `320`
   - Name: `Allow-App-Port`
   
   ![](img/inbound-rules-2.png)

5. Select **Add**.
6. Repeat steps 1 through 5 for every VM on the team.

After this, re-run the `curl http://<your_vm_public_ip>:8080/config.js` test from Part 3 on your own machine. It should now succeed for every VM individually, and return that specific VM's hostname. Confirm this before moving on, since the load balancer setup will be harder to debug if the individual VMs are not already reachable.

![](img/vm1-danish.png)

---

## 12. Part 5: Create the Load Balancer

One team member does this part while the others watch and follow along, since only one load balancer is needed per team. Everyone should still be logged into the shared resource group to see it happen live if working from separate laptops.

### 12.1 Create a Standard Public IP

1. Search for **Public IP addresses** and select **Create**.
2. Configure:
   - Resource group: the shared team resource group
   - Name: `pip-team01-breakout-lb`
   - SKU: Standard
   - Assignment: Static
   - Region: same as everything else
3. Select **Review + create**, then **Create**.

### 12.2 Create the Load Balancer Resource

1. Search for **Load balancers** and select **+ Create > Standard Load Balancer** from the dropdown.
   
   ![](img/create-load-balancer.png)

2. On the Basics tab:
   - Resource group: the shared team resource group
   - Name: `lb-team01-breakout`
   - Region: same as everything else
   - SKU: Standard
   - Type: Public
   - Tier: Regional

   ![](img/create-load-balancer-basics.png)

3. On the Frontend IP configuration tab, add a new frontend IP and select the Standard Public IP created in 12.1.

   ![](img/create-load-balancer-fip.png)

### 12.3 Create the Backend Pool

1. Open the newly created load balancer resource.
2. Select **Backend pools** from the left menu, then **Add**.
3. Name it, for example `bp-team01-breakout`.
4. Virtual network: select the shared `vnet-team01`.
5. Under IP configurations, select **Add**, and add each team member's VM one by one.
   
   ![](img/create-load-balancer-bep.png)

6. Select **Save**.

If a VM does not appear in the list here, the most likely reason is that it was created in a different virtual network. Confirm it was created following Part 2 exactly.

### 12.4 Create the Health Probe

1. Select **Health probes** from the left menu, then **Add**.
2. Configure:
   - Name: `hp-team01-breakout`
   - Protocol: HTTP. The Breakout app reliably returns a plain HTTP 200 on the root path with no login or state required, so there is no need to fall back to a plain TCP probe here.
   - Port: `8080`
   - Path: `/`
   - Interval: `5` seconds
   - Unhealthy threshold: `2`
   
   ![](img/create-load-balancer-hp.png)

   *note: either http or TCP is fine, as long as it's consistent across the lab*

3. Select **Add**.

### 12.5 Create the Load Balancing Rule

1. Select **Load balancing rules** from the left menu, then **Add**.
2. Configure:
   - Name: `rule-team01-breakout`
   - IP Version: IPv4
   - Frontend IP address: the frontend IP created in 12.1
   - Backend pool: `bp-team01-breakout`
   - Protocol: TCP
   - Port: `80`
   - Backend port: `8080`
   - Health probe: `hp-team01-breakout`
   - Session persistence: None (do not change this, see the important note in Section 13 about why this alone will not make a browser refresh alternate every time)
   - Idle timeout: `4` minutes (default is fine)

Notice the frontend port (`80`) and backend port (`8080`) are different, and that's intentional. A load balancing rule does not require them to match. The load balancer listens on port 80 for anyone visiting its public IP, so participants can just type `http://<public-ip>` with no port number, but internally it still forwards each request to port 8080 on whichever VM it picks, which is the actual port the container is listening on. Nothing about the VMs, the container, or the NSG rules changes because of this, only the load balancer's own frontend listener does.
   
   ![](img/load-balancer-rules.png)

3. Select **Add**.

![](img/load-balancer-review.png)

At this point the full chain exists: frontend IP, backend pool with all team VMs, a health probe checking them, and a rule connecting the two.

---

## 13. Part 6: Test and Prove Load Balancing Works

### 13.1 Important: why a browser refresh alone is not a reliable test

Before testing, understand this, since it is the single most confusing part of this whole module and every team will likely run into it.

Azure Standard Load Balancer works at Layer 4 (the transport layer). It distributes traffic based on a hash of source IP, source port, destination IP, destination port, and protocol, not per individual HTTP request. A browser tab keeps reusing the same source IP and source port, and often reuses the same open connection through keep-alive, across many refreshes. That combination means a single browser tab can land on the same VM for a long stretch, then suddenly jump to a different one once an idle connection times out and gets rehashed. This is normal, expected behavior for a Layer 4 load balancer, it is not a sign that Session persistence is misconfigured, and it is not a bug in the setup.

If you want every single page refresh to visibly alternate between backends every time with no exceptions, that requires a Layer 7 device (Azure Application Gateway), which makes routing decisions per HTTP request instead of per connection. That is a different Azure resource with its own setup, out of scope for this module. Standard Load Balancer, used here, is genuinely doing its job correctly even when a browser tab does not visibly alternate on every refresh.

### 13.2 Before You Test in a Browser: Disable Auto-HTTPS

Most modern browsers now try HTTPS first whenever you type a bare IP address or domain into the address bar, even if you never typed `https://` yourself. Your load balancer only serves plain HTTP, there is no TLS certificate configured on it, so this auto-upgrade will fail or show a security warning page instead of your app, even though nothing is actually wrong with the load balancer.

Two things fix this, do both:

1. **Always type the `http://` prefix explicitly.** Typing just `<public-ip>` or `<public-ip>/` into the address bar is what triggers the automatic HTTPS attempt in most browsers. Typing `http://<public-ip>` in full tells the browser exactly what you want and usually avoids the upgrade attempt entirely.
2. **If a warning page still appears** ("Your connection is not private," "This site can't provide a secure connection," or similar), your browser's HTTPS-only setting is turned on and is blocking the fallback rather than allowing it. Turn it off:
   - **Chrome or Edge**: go to `chrome://settings/security` (or `edge://settings/privacy`), find **Always use secure connections** (Chrome) or **Automatically switch to HTTPS connections whenever possible** (Edge), and turn it off.
   - **Firefox**: go to `about:preferences#privacy`, scroll to **HTTPS-Only Mode**, and set it to **Don't enable HTTPS-Only Mode**, or add an exception for this specific IP if you'd rather leave the setting on generally.
   
   ![](img/brave-https-disabled.png)
   *note: the image is taken from brave browser, but the concept is the same*

This only affects browser navigation. It has no effect on `curl`, which is why the loop in Section 13.3 works regardless of any browser setting.

### 13.3 The real test: curl loop, not browser refresh

1. Find the load balancer's public IP address, either from the Public IP resource created in 12.1 or from the load balancer's Overview page.
2. First, confirm the health probes are passing. Go to **Insights** or check each backend instance status under the backend pool. All VMs should show as healthy before testing traffic.
   
   ![](img/insight.png)

3. From your own local machine, not from inside either VM's SSH session, run:
   ```
   for i in $(seq 1 10); do
     curl -s http://<load_balancer_public_ip>/config.js
     echo ""
   done
   ```
   No port number is needed here, since the load balancer's frontend listens on port 80, the default for plain HTTP. Each `curl` call opens a brand new connection with no keep-alive reuse, which is exactly why this is a trustworthy test where a browser refresh is not. Hitting `/config.js` specifically, rather than the full HTML page, gives a clean one-line answer per request, for example:
   ```
   window.APP_CONFIG = { hostname: "budi" };
   window.APP_CONFIG = { hostname: "danish" };
   window.APP_CONFIG = { hostname: "budi" };
   ```
4. Record the output. This is the evidence that traffic is being distributed. A team should see requests answered by more than one VM across the 10 attempts.
   
   ![alt text](img/terminal-load-balancing-test.png)

5. Optionally, also open `http://<load_balancer_public_ip>` in a browser (with the `http://` typed explicitly, per Section 13.2) to see the actual game and confirm it loads correctly end to end. Do not treat a browser tab sticking to one hostname for a while as a failure, that is expected given Section 13.1. If you want to see a visible change in the browser without waiting for a connection to time out, opening a fresh private/incognito window for each check gets closer to the curl loop's behavior, though it is still not a guaranteed alternation on every single load.

![alt text](<img/Screenshot from 2026-08-31 23-48-59.png>) ![alt text](<img/Screenshot from 2026-08-31 23-49-08.png>)

If the curl loop itself, not just the browser, shows the exact same VM on all 10 requests with no exceptions, then check Session persistence in the load balancing rule (should be None) and confirm the health probe shows all backends as healthy rather than just one.

---

## 14. Part 7 (Optional but Recommended): Simulate a Failure

This step is short and makes the concept of health probes concrete.

1. SSH into one team member's VM.
2. Stop the running container:
   ```
   docker stop breakout
   ```
3. Wait about 15 to 20 seconds for the health probe to detect the change (based on the interval and threshold set in Section 12.4).
4. Check the backend pool health status again. That VM should now show as unhealthy.
5. Re-run the curl loop against `/config.js` from Section 13.3. Every response should now show only the remaining healthy VM's hostname.
6. Restart the container:
   ```
   docker start breakout
   ```
7. After the next successful probe interval, confirm the VM returns to a healthy state and starts receiving traffic again, and reappears in the curl loop results.

This demonstrates the actual purpose of a health probe: automatically routing around a failed instance without anyone manually intervening.

---

## 15. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Backend pool is empty or a VM does not appear as an option | VM is in a different virtual network than the load balancer | Recreate the VM inside the shared `vnet-team01`, or confirm the correct VNet was selected during creation |
| Health probe shows all backends unhealthy | No NSG rule allowing port 8080 | Complete Part 4 for every VM |
| Health probe shows unhealthy but curl works directly to the VM | Health probe path or protocol mismatch | Confirm the probe is HTTP on path `/`, port `8080`, matching Section 12.4 exactly |
| Browser refresh keeps showing the same VM hostname for a while, then eventually changes | This is expected, not a bug. Standard Load Balancer distributes at Layer 4, based on a hash of source IP and port plus connection reuse, not per HTTP request | Do not judge distribution by browser refresh. Use the curl loop against `/config.js` from Section 13.3, which opens a fresh connection each time and gives a reliable answer |
| Browser shows a security warning, or "connection is not private," when visiting the load balancer's IP | The browser tried to auto-upgrade the request to HTTPS, which this load balancer does not serve | Always type `http://` explicitly in the address bar, and if the warning still appears, disable the browser's HTTPS-only setting per Section 13.2 |
| The curl loop itself, not just the browser, shows the exact same VM every single time with zero exceptions | Session persistence is not set to None | Edit the load balancing rule and set Session persistence to None |
| Cannot reach the app through a VM's public IP directly | NSG rule missing or wrong port | Recheck Part 4 for that specific VM |
| `docker logs breakout` shows the hostname as `unknown` instead of the real VM name | The container was started without `-e VM_HOSTNAME=$(whoami)`, or `$(whoami)` returned nothing on that shell | Re-run the `docker run` command from Part 3 with the flag included, confirm a plain `whoami` command works on that VM first |
| Teammate cannot see the shared resource group | Role assignment not completed, or invitation not accepted | Recheck Part 0, confirm Contributor role was assigned to the correct email |
| Error when creating a VM: a resource provider like Microsoft.Compute or Microsoft.Storage is not registered, and the account does not have permission to register it | Contributor access was granted at the resource group level only, which is not enough to register a resource provider for the first time | Have the Team Owner sign in and register the missing providers under Subscriptions > Settings > Resource providers, as described in Part 0, step 6. This only needs to be done once per subscription |

---

## 16. Cleanup Reminder

Standard Load Balancer, Standard Public IP, and running VMs all consume Azure for Students credit continuously while they exist, not only while in active use. If the final project will reuse this exact setup over the coming week, it is fine to leave it running, but the team should:

- Stop (deallocate) VMs when not actively working, not just close the SSH session
- Monitor remaining credit in the Azure Portal under **Cost Management**
- Fully delete the resource group at the end of the final project once the showcase is done

---

## 17. Deliverable / Checkpoint Summary

By the end of this session, each team should have produced:

1. A shared resource group containing a virtual network, 2 to 3 VMs (one per teammate), and one load balancer
2. Each VM running the Breakout LB Demo container with its own correctly injected hostname, confirmed via `docker logs`
3. NSG rules allowing port 8080 on every VM
4. A working load balancer with a healthy backend pool
5. A screenshot or terminal recording of the `curl` loop against `/config.js` showing requests answered by more than one VM's hostname
6. (Optional) A screenshot showing the backend pool correctly marking a stopped instance as unhealthy

---

## 18. Suggested Timing

| Section | Suggested duration |
|---|---|
| Concepts and Team Environment Setup (Parts 0 to 1) | 30 minutes |
| VM creation and app verification (Parts 2 to 3) | 40 minutes |
| NSG configuration (Part 4) | 15 minutes |
| Load balancer creation (Part 5) | 45 minutes |
| Testing and proof (Part 6) | 20 minutes |
| Failure simulation (Part 7) | 15 minutes |
| Buffer for troubleshooting | 15 minutes |
| **Total** | **About 3 hours** |

Adjust based on how much time your session actually has. If time is short, Part 7 is the first thing to cut, since it is optional.