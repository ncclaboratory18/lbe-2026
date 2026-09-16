# Lab Based Education (LBE) Final Capstone Project Specification

## Overview

This document describes the take home final project for the Lab Based Education (LBE) workshop. It is meant to be read carefully before you start, and referenced throughout the week as you build.

The workshop has four meetings. Meeting 1 covered Azure fundamentals and VM creation. Meeting 2 covered Docker. Meeting 3 covered Azure Load Balancer, using the Standard SKU only, since the Basic SKU was retired on September 30, 2025. Meeting 4 is a live showcase and demo day.

This final project is the work you do between Meeting 3 and Meeting 4, roughly one week. You will build a small but complete piece of cloud infrastructure: multiple VMs, each running your app in a Docker container, sitting behind a load balancer that distributes traffic between them.

You are expected to be a beginner with Azure, Docker, and cloud infrastructure in general, but comfortable with basic coding and basic web or backend development. Nothing in this project assumes prior infrastructure experience beyond what was covered in Meetings 1 through 3.

## Team Formation and Roles

Work in teams of 2 to 3 people. Each team member will create their own Azure VM using their own Azure for Students subscription.

Because the load balancer's backend pool requires every VM in the pool to be in the same virtual network, all team VMs must live inside one shared resource group and one shared virtual network, even though each of you normally works in your own separate subscription.

To make this possible, one team member should volunteer to be the **Team Owner**. The Team Owner is responsible for:

1. Creating the shared resource group and the shared virtual network inside their own subscription.
2. Granting the other team members Contributor access to that resource group via Azure IAM, so they can create their own VM inside the shared environment using their own login.

Before you pick a Team Owner, talk as a team about billing. Whichever subscription hosts the shared resource group is the one that gets billed for everything created inside it, regardless of who actually created each resource. This is a normal part of how Azure resource groups and subscriptions work, so decide together who is comfortable taking on that role before you start building.

## Required Architecture

Your final project must include the following, all inside the one shared resource group described above:

- One shared virtual network.
- 2 to 3 Azure VMs, one per team member, each running Ubuntu on a Standard_B1s size (this size is free tier eligible).
- Each VM running the team's chosen app inside a Docker container, built from a Dockerfile.
- One Azure Standard Load Balancer sitting in front of all the team's VMs, configured with:
  - A backend pool containing every team VM.
  - A health probe checking the app's port.
  - A load balancing rule with the frontend port set to 80 and the backend port set to whatever port your app actually listens on. Azure Load Balancer allows the frontend and backend ports to differ, and setting the frontend port to 80 is what lets anyone visit your app using the bare load balancer IP address with no port number in the URL.
  - Session persistence on the load balancing rule set to **None**.

There is no fixed convention for what path or port your health probe checks. Configure it based on how your own app responds, as long as it correctly reports a VM as healthy when the app is actually up and unhealthy when it is not.

## Registering Resource Providers (a gotcha to expect)

Once a teammate has Contributor access at the resource group level, their first attempt to create a VM will commonly fail with an error similar to:

`Resource provider Microsoft.Compute is not registered for this subscription and you don't have permission to register it.`

This is not a mistake on your part. Registering a resource provider for the first time in a subscription requires subscription level permissions, and Contributor access granted at the resource group level is not enough to do that.

The fix: the Team Owner, who has subscription level access, needs to manually register the `Microsoft.Compute` and `Microsoft.Storage` resource providers once, before teammates try to create their VMs. This is done from the Azure Portal under Subscriptions, then Settings, then Resource providers. Do this early, ideally as one of the first things the Team Owner does after creating the shared resource group, so teammates are not blocked later in the week.

## The Application

Each team member's VM should run a portfolio website for that team member, built with HTML, CSS, and JavaScript, served with Nginx as the web server, and packaged inside a Docker container. The application should deploy cleanly in a Docker container and works correctly behind the load balancer. 

## Understanding How the Load Balancer Actually Behaves

This is important enough that it is worth reading twice.

Azure Standard Load Balancer distributes traffic using a five tuple hash made up of source IP, source port, destination IP, destination port, and protocol. This decision happens at Layer 4, and it is not made fresh for every single HTTP request.

In practice, this means that if you sit in a browser tab and refresh repeatedly, you will often keep landing on the same backend VM for a while before the traffic switches to a different one. This happens because your browser tends to reuse the same source IP, the same source port, and often the same already open connection. This is expected, correct load balancer behavior. It is not a sign that your load balancer is misconfigured.

Because of this, browser refresh is not a reliable way to prove your load balancer is distributing traffic. To prove distribution, use a script that opens fresh, independent connections instead, for example a curl loop run from a local terminal, hitting the load balancer's IP address repeatedly and printing which VM answered each time. This is the method you should use for the evidence of distribution deliverable below.

## A Note on HTTPS and Browser Warnings

Your load balancer serves plain HTTP, with no TLS certificate attached. Some browsers will automatically try to upgrade a bare IP address to HTTPS, which will either fail outright or show a security warning, since there is nothing listening for HTTPS on the other end.

To avoid this, always type the `http://` prefix explicitly when visiting your load balancer's IP address. If a warning still appears after doing that, check your browser's HTTPS only setting, sometimes labeled "always use secure connections," and temporarily allow the plain HTTP connection for testing.

## Deliverables

Each team must submit the following:

- [ ] One shared resource group containing one virtual network, 2 to 3 VMs (one per team member), and one load balancer, configured as described in the Required Architecture section above.
- [ ] Each VM running the team's app inside a Docker container.
- [ ] NSG rules on every VM that allow traffic on the app's actual port.
- [ ] A working, healthy load balancer backend pool, with all VMs reporting healthy.
- [ ] Evidence that traffic is actually being distributed across more than one VM, gathered using the curl loop method described above, not browser refresh alone.
- [ ] A GitHub repository containing your code and your Dockerfile.
- [ ] Documentation inside that same repository containing your evidence of distribution (there is no required format for this, plain text output, a screenshot, or however you choose to capture it is fine, as long as it clearly shows requests being answered by more than one VM).
- [ ] A short live demo prepared for Meeting 4.

## Evidence of Distribution

Your evidence that the load balancer is distributing traffic across more than one VM should be included as documentation inside your GitHub repository, alongside your code. There is no specific format required. What matters is that it clearly shows the load balancer's IP being hit repeatedly, using the curl loop method, with responses coming back from more than one VM.

## Submission

Submit your project by sharing a link to your team's GitHub repository through the Google Form that will be provided to you. That repository should contain your code, your Dockerfile, and your documentation showing evidence of distribution.

The deadline for submission is 18:00, one week from Meeting 3.

There is no separate grading rubric included in this document.

## Demo Day (Meeting 4)

Each team should prepare a short live demo of their working project for Meeting 4. Aim for a demo that fits into roughly 5 to 7 minutes, since this is what past sessions have used as a guideline. This timing may be adjusted depending on the actual number of teams and the time available on the day, so listen for any updates closer to Meeting 4.

## Optional Stretch Goals

If your team finishes the required deliverables early, here are a few optional stretch goals you can attempt. These are entirely optional and are not required for a complete submission:

- A GitHub Action that automatically builds and pushes your Docker image on every push.
- A simulated failure demonstration: stop one VM's container, show that the load balancer correctly marks that VM as unhealthy and reroutes traffic to the remaining VMs, then show it recover once the container is restarted.
- HTTPS via a reverse proxy in front of your app.
- A basic load testing script that visualizes how requests are distributed across your VMs.

Good luck, and enjoy building this. If you get stuck on something not covered here, that is a normal part of working with real infrastructure, take a step back, check the Azure Portal's error messages carefully, and work through it as a team.