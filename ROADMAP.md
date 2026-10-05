# Poltergeist Roadmap

**Core rule:** `1 image = 1 app = 1 workload`. Each workload is sent whole to one machine. Nothing in this roadmap splits a workload across machines.

Each phase produces something that works and can be demonstrated. Dates are left out until the first prototype shows how long things really take.

**Legend:** `[ ]` not started, `[~]` in progress, `[x]` done

---

## Phase 0: Design

**Goal:** Agree on the scope, the formats, and the first demo.

- [ ] Write down the core rule and what is in and out of scope
- [ ] Define the workload spec (image, platform, resources, inputs, outputs)
- [ ] Define the machine registry format (OS, arch, RAM, GPU, modes, cost)
- [ ] Choose the CLI and agent language (Go or Python)
- [ ] Pick the first demo workload (for example: a C/C++ build or a video encode)
- [ ] Write a short threat model

**Done when:** a one-page design exists and Phase 1 is scoped.

---

## Phase 1: Two-machine prototype

**Goal:** Run one workload on a second machine from the terminal.

- [ ] CLI: `poltergeist run ./job.yaml --on <machine>`
- [ ] Reach the second machine over SSH (same network)
- [ ] Run the image with Docker on that machine
- [ ] Upload inputs, stream logs live, download outputs

**Done when:** the demo workload runs on the second laptop and the result appears on your first laptop with one command.

---

## Phase 2: Registry and matcher

**Goal:** Know which machines can run which workloads.

- [ ] Machine registry file and `poltergeist machines list`
- [ ] Compatibility check: OS, CPU architecture, RAM, GPU, supported modes
- [ ] Clear rejection messages ("image is linux/amd64, laptop2 is arm64")
- [ ] `--auto`: pick the cheapest compatible machine (own machines cost 0)
- [ ] Show the chosen machine and estimated cost before running

**Done when:** `--auto` picks a sensible machine and an incompatible `--on` is refused with a useful message.

---

## Phase 3: Packaging and transfer

**Goal:** Make images and files move reliably and quickly.

- [ ] Registry support for images (Docker Hub, GHCR, or a private registry)
- [ ] Multi-architecture builds (`linux/amd64` and `linux/arm64`)
- [ ] Content-addressed cache so unchanged files are not re-sent
- [ ] Storage modes: ephemeral, sync-up, sync-down
- [ ] Measure transfer time versus compute time

**Done when:** a repeat run is clearly faster than the first, and large inputs are handled without re-uploading everything.

---

## Phase 4: Reliability and safety

**Goal:** Survive laptops that sleep and protect the user's files.

- [ ] Heartbeats and job timeouts
- [ ] Safe retry on a different machine (jobs must be rerunnable)
- [ ] Resource limits (CPU, RAM, time) and "run only when idle" for own machines
- [ ] Battery and temperature awareness for laptops
- [ ] Folder access limited to one chosen folder, with a read-only option
- [ ] Snapshot before a run and trash instead of delete

**Done when:** closing the lid on the worker laptop never loses user data, and the job is retried or reported clearly.

---

## Phase 5: Cloud machines

**Goal:** Add rented machines to the same pool.

- [ ] Provision and destroy a VM on one provider (AWS or Azure)
- [ ] Per-second usage tracking and automatic shutdown when idle
- [ ] Price lookup from the provider's pricing API (include spot prices)
- [ ] Cloud machines appear in the registry and are used by `--auto`
- [ ] Spending limits per workload and per month

**Done when:** `--auto` uses your own idle machine when it fits and falls back to a cloud VM when it does not, then cleans up.

---

## Phase 6: More operating systems

**Goal:** Support workloads that are not Linux containers.

- [ ] Native mode for same-OS jobs (Windows app on a Windows machine, Mac app on a Mac)
- [ ] Windows VM images for Windows workloads on cloud machines
- [ ] Mac mini support (own Macs first; rented Macs after checking cost and minimum rental time)
- [ ] Review Apple and Microsoft license terms before offering rented Windows or macOS
- [ ] Optional experiment: Wine-based "compat mode" for Windows apps, with a warning

**Done when:** one Windows workload and one macOS workload each run on a matching machine through the same CLI.

---

## Phase 7: Machines beyond your local network

**Goal:** Reach your devices from anywhere.

- [ ] Pairing with a one-time code
- [ ] Agents that connect outbound to a control server (no port forwarding)
- [ ] Encrypted overlay network (WireGuard or Tailscale)
- [ ] mTLS or per-device keys for authentication
- [ ] Optional LAN discovery (mDNS)

**Done when:** a laptop at home can run a workload sent from another city, with all traffic encrypted.

---

## Phase 8 (optional): Interactive apps

**Goal:** Support whole apps that need a screen, only if earlier phases succeed.

- [ ] Choose a streaming approach (Xpra, Sunshine/Moonlight, NICE DCV, WebRTC)
- [ ] Mount and hybrid file-access modes with a write-back cache
- [ ] Measure latency from the user's region
- [ ] Review software licensing for hosted use

**Done when:** one GUI app (still one image, one app, one workload) is usable over the network with acceptable latency.

---

## Out of scope

- Splitting one workload across several machines
- Moving part of a running program to another machine
- Several apps in one image
- Full virtual desktops
- Renting out machines to strangers
- Enterprise features (SSO, compliance certifications)

## Open questions

- Which demo workload shows the clearest benefit: compile, render, or encode?
- How large can inputs be before transfer time defeats the purpose?
- Should Windows and macOS jobs be packaged as VM images, or run natively on the machine's own OS?
- What is the simplest safe way to pair machines across the internet?
