# lbe-2026
Lab Based Education 2026 Modules

---

## Module 0 — Prerequisites (self-paced, sent before Meeting 1)

Goal: everyone arrives at Meeting 1 with a working environment, so zero setup time is wasted live.

**Contents of the guide:**
1. Claim Azure for Students using their student email (walkthrough with screenshots, note on credit limits/expiry)
2. Install a Linux environment:
   - Windows → WSL2 + Ubuntu (step-by-step, plus "open Ubuntu terminal" sanity check)
   - Mac/Linux → confirm terminal access, or note if any adjustments needed
3. Install/verify SSH client (usually built-in, but confirm `ssh -V` works)
4. Install Git (needed to `git clone` the provided web app later)
5. Create/verify a GitHub account (for pulling the sample app repo)
6. A short **"proof of setup" checklist** they self-report or submit (e.g., screenshot of `ssh -V`, `git --version`, Azure portal showing active subscription) — gives you a way to catch stragglers before Meeting 1 instead of discovering it live
7. Optional: a short FAQ / troubleshooting section for common WSL install issues (this is usually where people get stuck)

Consider a short "office hours" or Discord/WhatsApp channel for setup help before Day 1, since this is take-home and self-paced — someone will get stuck on WSL and silently not show up otherwise.

---

## Meeting 1 — Microsoft Azure

**Objective:** Understand core Azure concepts and get comfortable creating and accessing a VM.

- Quick recap check: confirm Module 0 setup worked (troubleshoot stragglers first 10-15 min)
- Concepts (short, practical): resource groups, regions, VM sizes/tiers, what "Free/Student credit" actually covers
- **Hands-on 1:** Create a resource group + VM via Azure Portal (Ubuntu image, B1s or similar free-tier-eligible size)
- **Hands-on 2:** SSH into the VM from their local terminal (using the key pair generated at VM creation)
- **Hands-on 3:** Basic Linux sanity checks on the VM (update packages, check IP, maybe run a simple `python3 -m http.server` and hit it from browser via public IP — nice "it's alive" moment)
- Wrap-up: note down their VM's public IP / how to restart it — they'll need to keep this pattern in mind for Meeting 3

**Deliverable/checkpoint:** Screenshot of successful SSH session + something served over HTTP from the VM.

---

## Meeting 2 — Docker

**Objective:** Understand containers and get the provided web app running in Docker, both locally and on their Azure VM.

- Concepts (short): image vs container, Dockerfile, why containers > "just run it on the VM directly"
- **Hands-on 1:** Install Docker on their VM (or locally in WSL, then transfer skill to VM)
- **Hands-on 2:** `git clone` the lab-provided sample web app (the instance-ID endpoint app you're building)
- **Hands-on 3:** Write/inspect a Dockerfile for it, `docker build`, `docker run` locally — confirm the endpoint returns instance ID/hostname
- **Hands-on 4:** Push the image to a registry (Docker Hub, or Azure Container Registry if you want tighter Azure integration)
- **Hands-on 5:** Pull + run that same image on their Azure VM from Meeting 1, confirm it's reachable via public IP:port

**Deliverable/checkpoint:** Their Dockerized app running and reachable on their own Azure VM.

*Note: since you're providing the app, spend more of this meeting on Docker mechanics (build/run/push/pull) rather than app logic — that's the actual point of the module.*

---

## Meeting 3 — Load Balancing (using Azure)

**Objective:** Combine VMs + Docker + Azure Load Balancer as a team, and prove traffic is being distributed.

- Concepts (short): what a load balancer does, health probes, backend pools, round-robin basics
- Teams regroup (2-3 people)
- **Hands-on 1:** Each member ensures their own VM (from Meetings 1-2) has the Dockerized app running and reachable
- **Hands-on 2 (team):** Create an Azure Load Balancer, add all team members' VMs as a backend pool, configure health probe + load balancing rule
- **Hands-on 3 (team):** Hit the load balancer's public IP repeatedly (browser refresh, or a simple curl loop) and observe the instance-ID endpoint rotating across different VMs
- Discuss: what happens if you stop one VM's container — does the LB route around it? (great teachable moment on health probes)

**Deliverable/checkpoint:** Team screenshot/recording of repeated requests hitting different backend instances via the LB's public IP.

*This is deliberately structured as a compressed rehearsal of the final project — same components, same steps, just guided live instead of independent.*

---

## Final Project (take-home, ~1 week) — Meeting 4 is showcase day

**Task:** Teams extend what they built in Meeting 3 into their own final version — same architecture (VMs + Docker + Load Balancer), but now with more ownership/polish, and freedom to add flair.

**Required:**
1. 2-3 VMs (one per team member), each running the Dockerized app
2. Azure Load Balancer distributing traffic across them
3. A clear way to demo traffic distribution (refresh loop, script, or simple dashboard showing hits per instance)

**Optional stretch goals** (for teams who finish early — this is where CI/CD can sneak in painlessly):
- Add a GitHub Action that auto-builds and pushes the Docker image on every push
- Add a simple health/status page instead of raw JSON responses
- Simulate load with a script (e.g., loop of curl requests or a basic load-testing tool) and visualize distribution
- HTTPS via a reverse proxy

**Meeting 4 — Showcase Day**
- 5-7 min per team: live demo (hit the LB, show distribution) + 2 min walkthrough of what they built/changed
- Optional light "judging" on: does it actually load balance, clarity of demo, stretch goals attempted
- Closing recap: tie the whole arc together (Prereqs → Azure → Docker → Load Balancing → their own scaled deployment)
