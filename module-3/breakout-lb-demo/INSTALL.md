# Breakout Load Balancer Demo: Install Guide

This is the specific install guide for this app only. It assumes you already
have a working VM with Docker installed (Meeting 1 and 2 territory), and
that you will run this on two or more VMs behind a load balancer.

## 1. Get the files onto the VM and install docker

From your local machine, copy the whole project folder to the VM:

```
scp -r breakout-lb-demo <username>@<vm_public_ip>:~/
```

Then SSH in:

```
ssh <username>@<vm_public_ip>
cd breakout-lb-demo
chmod +x install-docker.sh
sudo ./install-docker.sh
```

note:

> If this error occurs:
> ```
> permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
> ```
> run this:
> ```
> sudo usermod -aG docker $USER
> newgrp docker
> ```

## 2. Build the image

```
docker build -t breakout-lb-demo .
```

## 3. Run the container

This is the one command that matters most. VM_HOSTNAME must be passed in
explicitly, using the shell's own `$(whoami)` substitution, so the
container picks up this specific VM's real hostname, not its own internal
container hostname:

```
docker run -d --name breakout -p 8080:8080 -e VM_HOSTNAME=$(hostname) breakout-lb-demo
```

Check the logs to confirm the hostname was picked up correctly:

```
docker logs breakout
```

You should see a line like:

```
Starting Breakout LB demo, hostname injected as: vm-team01-danish
```

If it says `unknown` instead, `$(hostname)` did not resolve to anything on
this shell, check with a plain `hostname` command on its own first.

## 4. Open the NSG rule for port 8080

Same as before: in the Azure Portal, go to this VM's Networking page, and
add an inbound rule allowing TCP port 8080, if it is not already open from
a previous app on this VM.

## 5. Verify from your own laptop, not from inside the VM

```
curl -s http://<vm_public_ip>:8080/ | head -5
```

You should get back HTML. Then open `http://<vm_public_ip>:8080` in a
browser and confirm the hostname shown on screen, both in the header text
and in the block wall, matches this VM's actual hostname.

## 6. Repeat on the second VM

Same three steps: build (or just run, if you push the image to a registry
instead of rebuilding on each VM), run with `-e VM_HOSTNAME=$(hostname)`,
open the NSG rule. Confirm the second VM shows a different hostname than
the first before moving on to the load balancer setup.

## Notes for the load balancer step

- Health probe: use HTTP, port 8080, path `/`. Unlike the earlier ITSPay
  frontend, this app reliably returns HTTP 200 on `/` with no login or
  state required, so an HTTP probe is safe to use here, not just TCP.
- Load balancing rule: port 8080 to backend port 8080, session persistence
  set to None, same as before.
- To prove distribution, you do not need a curl loop and container logs
  this time. Just refresh the browser pointed at the load balancer's
  public IP repeatedly. The header text and block wall will visibly change
  between VM hostnames as the load balancer rotates you between backends.
