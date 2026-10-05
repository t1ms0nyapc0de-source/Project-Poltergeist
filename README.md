# Poltergeist

> Package a workload once, then run the whole thing on any machine you choose (your second laptop, a Mac mini, a cloud VM), or let Poltergeist pick the cheapest one that fits.

**Status: early planning.** The commands and features below describe the intended design. Nothing here is implemented yet. See [ROADMAP.md](ROADMAP.md) for the plan.

---

## Core rule

```
1 image = 1 app = 1 workload
```

- An **image** (or package) contains exactly **one app**.
- Running that app once is exactly **one workload** (one job).
- A workload is sent **whole** to **one machine**. It is never split across machines, and parts of a running program are never moved.
- To run several apps, create several images and submit several workloads.

This keeps every decision simple: the scheduler only needs to ask, "can this machine run this one image?"

## Why

Hardware (GPUs, RAM, Macs) keeps getting more expensive, but most people only need powerful machines for a few hours at a time. Many people also already own spare machines (an old laptop, a Mac mini) that sit idle. Cloud providers are built for companies: complex setup, confusing pricing, and long minimums (for example, a 24-hour minimum for Mac instances on AWS).

Poltergeist treats every machine you can reach as one pool: your own devices first (they cost nothing extra), and the cloud when you need more.

## What it does

```bash
# Planned usage
poltergeist machines add                  # pair a machine (laptop, Mac mini, cloud VM)
poltergeist machines list

poltergeist run ./job.yaml --on laptop2   # manual: choose the machine
poltergeist run ./job.yaml --auto         # automatic: cheapest machine that fits
```

## How it works

```
CLI ──> Matcher ──> picks one machine ──> Agent on that machine
 |                                          |
 |   package + inputs  ───────────────────> runs the workload
 |   <─────────────────── logs + outputs ───┘
```

1. You describe the workload (image, platform, resources, inputs, outputs).
2. The **matcher** checks every known machine and rejects the ones that cannot run it.
3. You pick one (`--on`), or the matcher picks the cheapest compatible one (`--auto`).
4. The **agent** on that machine receives the image and inputs, and runs the workload.
5. Logs stream back live, outputs come home, and the machine is released.

## Main components

| Component | Job | First version |
|---|---|---|
| Machine registry | Knows each machine's OS, CPU architecture, RAM, GPU, supported modes, and cost | A YAML file |
| Matcher | Filters by compatibility, then sorts by cost (own machines cost 0) | A single function |
| Agent | Runs on each machine, receives a workload, runs it, reports back | Small Go or Python program over SSH |
| Transfer layer | Moves images, inputs, and outputs | Docker registry plus rsync |

## Workload spec

```yaml
name: render-job
image: myrepo/render:1.0         # one image = one app = one workload
platform: linux/amd64            # OS and CPU architecture the image needs
resources: { cpu: 8, ram: 16G, gpu: 0 }
inputs:  ./scene                 # uploaded before the run
outputs: ./result                # downloaded after the run
```

## Machine registry

```yaml
machines:
  - name: laptop2
    os: windows
    arch: amd64
    modes: [container, native]
    cpu: 8
    ram: 16G
    cost: 0
  - name: macmini
    os: macos
    arch: arm64
    modes: [container, native]
    cost: 0
  - name: aws-c7g
    os: linux
    arch: arm64
    modes: [container]
    cost: 0.58/h
```

## What can run where

The matcher gives a clear error when nothing fits, for example: "this image is linux/amd64, but laptop2 is arm64".

| Image type | Can run on |
|---|---|
| Linux container | Linux directly. Windows and macOS machines run it inside a Linux VM (Docker Desktop, Colima). The CPU architecture must match, or be emulated (slower) |
| Windows app | Windows machines only (native, or a Windows VM image) |
| macOS app | Mac machines only |

A container does not remove OS differences; it carries the app's dependencies, not the kernel. The OS and CPU architecture are therefore part of every workload's requirements.

## Scope

**In scope**
- Whole-workload offload to one chosen machine
- Manual or automatic (cheapest) machine choice
- Own machines and cloud machines in one pool
- Disk access through upload and download (and later mounting) with safeguards

**Out of scope**
- Splitting one workload across several machines
- Moving part of a running program to another machine
- Several apps in one image
- Full virtual desktops
- Renting out machines to strangers

## Planned features

- One-command remote execution
- Manual machine choice, or automatic cheapest match
- Compatibility checks before sending anything
- Per-second billing for cloud machines, no minimum commitments
- Incremental file sync and caching
- Live log streaming
- Automatic shutdown of idle cloud machines
- Safeguards for local files (chosen folder only, read-only option, snapshot, trash instead of delete)

## Existing tools and how this differs

Related tools exist: Kubernetes/k3s, Nomad, Tailscale, Ray, distcc, AWS Batch, Modal, Amazon WorkSpaces, Azure Virtual Desktop. Poltergeist aims to differ by being:

- **One pool**: your own devices and the cloud, treated the same way
- **Simple**: one CLI and one rule (1 image = 1 app = 1 workload), not a cluster to administer
- **Cost-aware**: own machines first, cheapest cloud second, per-second billing
- **Aimed at students and small developers**

## Tech stack (planned)

| Area | Choice |
|---|---|
| CLI and agent | Go or Python |
| Packaging | Docker / OCI images (multi-architecture) |
| File transfer | rsync/SFTP, S3-compatible storage |
| Remote access | SSH first; outbound agent connections, WireGuard or Tailscale later |
| Cloud provisioning | Cloud SDKs or Terraform |
| Sandboxing | Container limits first; gVisor or Firecracker if sharing with others |

## Known challenges

- **OS and CPU architecture** decide where a workload can run; there is no universal translator.
- **macOS** only runs on Apple hardware, with limits on virtual machines, and Mac rentals are expensive.
- **Windows** needs a Windows license, and hosting rules are restrictive.
- **Data transfer** can cancel the benefit for large inputs, so caching matters.
- **Laptops disappear** (sleep, lid closed, Wi-Fi lost), so jobs need timeouts and safe retries.
- **Home networks** use NAT, so reaching a machine over the internet needs an overlay network or outbound agents.
- **Security**: running code on a machine needs limited folder access and encrypted connections.

## Roadmap

See [ROADMAP.md](ROADMAP.md).

## Contributing

The project is at the idea stage. Feedback, design suggestions, and issues are welcome.

## License

To be decided.
