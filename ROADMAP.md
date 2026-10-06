# Poltergeist Roadmap

**Core rule:** `1 image = 1 app = 1 workload`. A workload is sent whole to one machine. Nothing in this roadmap splits a workload across machines.

The order follows the life of a workload: **package it, script it, send it, unpack and run it.** Each phase produces something that works and can be demonstrated. Dates are left out until the first prototype shows how long things really take.

**Legend:** `[ ]` not started, `[~]` in progress, `[x]` done

---

## Foundations (done)

- [x] Scope: whole-workload offload to one chosen machine (own machines and cloud)
- [x] Core rule: 1 image = 1 app = 1 workload
- [x] Image contract drafted (`templates/CONTRACT.md`): fixed start command `/usr/local/bin/workload`, inputs in `/data/in`, outputs in `/data/out`, logs to stdout/stderr, exit code 0 = success, non-root user, no ports or secrets, labels

---

## Phase 1: Packaging design with Docker

**Goal:** For every kind of app, know how it is packaged, what it needs, and which machines can run it.

### 1.1 Linux distributions (start here)

- [x] Sample workload (C++ word counter) and draft templates: `cpp-cmake`, `python`, `linux-binary`
- [ ] Build and run each template with Docker on a real machine, and fix what fails
- [ ] Multi-architecture builds (`linux/amd64` and `linux/arm64`) pushed to a registry
- [ ] `sniff`: read a file without running it and report type, CPU architecture, libc (glibc or musl), minimum glibc version, and needed shared libraries
- [ ] `resolve`: turn those facts into a base image, a package list, and a `platform`
  - [ ] Base images: Debian/Ubuntu for glibc programs, Alpine for musl programs
  - [ ] Pick a base new enough for the program's glibc requirement
  - [ ] Map needed libraries to distro packages automatically (apt-file index)
  - [ ] Fallbacks: copy libraries into `lib/`, trace a run for libraries loaded at run time, then ask the user
- [ ] More Linux templates: Node, Java, Go, Rust, Makefile-based C/C++
- [ ] Use the user's own `Dockerfile` or an existing image when they have one
- [ ] Decide how `poltergeist pack` calls the build (`-f` template path plus the app folder as context, per-template `Dockerfile.dockerignore`)

**Done when:** a C++ project, a Python script, and a prebuilt Linux binary each become an image that runs correctly on both an x86 and an ARM Linux machine.

### 1.2 Windows

- [ ] Decide the Windows package types and when each is used:
  - [ ] Windows container image for console apps (runs on Windows machines in Windows-container mode only)
  - [ ] Native bundle (folder with the `.exe`, its DLLs, and a manifest) for apps that cannot be containerized
  - [ ] Windows VM image for apps that need a full Windows install
  - [ ] Wine inside a Linux image as an optional, experimental "compat mode"
- [ ] Bundling rules for `.exe` apps: static linking (`/MT`), DLL list (`dumpbin /dependents`), required runtimes (Visual C++ redistributable, .NET)
- [ ] Windows version matching for container base images
- [ ] Template: `windows-console`
- [ ] Review Windows licensing for hosted use before offering rented Windows machines

**Done when:** one Windows console app is packaged and runs on a Windows machine, and the package says clearly which Windows versions it supports.

### 1.3 macOS

- [ ] Linux images on a Mac: run through a Linux VM (Colima, Lima, Apple's `container`), including Rosetta for `amd64` images on Apple Silicon
- [ ] macOS apps: choose the package type
  - [ ] macOS VM image (stored in an OCI-compatible registry)
  - [ ] Native run in a temporary user account
- [ ] Binary facts for macOS: Mach-O architecture (arm64 or x86_64), minimum macOS version, code signing and notarization
- [ ] Review Apple's license terms (macOS only on Apple hardware, limited VMs per Mac) and cost (rental minimums)

**Done when:** a Linux image runs on a Mac mini, and one macOS command-line app runs through the chosen macOS package type.

### 1.4 Other app types

- [ ] Scripts with a `#!` line, packaged with the right interpreter
- [ ] Java `.jar`, WebAssembly (`.wasm`), AppImage, and `.deb` / `.rpm` packages
- [ ] GPU workloads (CUDA base images) and their host requirements
- [ ] File-type detection that routes each file to the right template

### 1.5 Packaging rules for every type

- [ ] One manifest format for every package (platform, resources, inputs, outputs, arguments)
- [ ] Image contract version 1 finalized, with a checker that verifies an image follows it
- [ ] A compatibility table: package type vs machine OS and CPU

---

## Phase 2: Bash prototype

**Goal:** Automate packaging and running with simple scripts before writing real software.

- [ ] `pack.sh`: detect the app, pick a template, run `docker build` / `buildx`
- [ ] `send.sh`: transfer the image and inputs to a target machine (`ssh`, `rsync`, `docker save | ssh ... docker load`)
- [ ] `run.sh`: start the workload on the target, stream logs, report the exit code
- [ ] `fetch.sh`: bring the outputs back
- [ ] A minimal `job.yaml` reader (using `yq` or `jq`)
- [ ] Machine list in a plain file (name, address, OS, architecture)
- [ ] Run the scripts on Windows through WSL or Git Bash, and on Linux and macOS natively
- [ ] Record what is awkward in bash (error handling, Windows targets, parsing) to decide what to rewrite

**Done when:** one command packs a workload on your PC and runs it on a second machine over SSH, with logs streaming back and outputs returned.

**After this phase:** decide whether to rewrite the scripts as a single program (Go or Python) once the flow is proven.

---

## Phase 3: Network protocol and transport layer

**Goal:** Move packages, inputs, logs, and results reliably between any two machines.

- [ ] Define the messages: submit job, accept or reject, status, log line, cancel, result, heartbeat
- [ ] Transport for version 1: SSH and rsync (already used by the bash prototype)
- [ ] Image transfer options: registry pull, or direct `docker save` / `load` over the connection for machines without registry access
- [ ] Resumable and compressed transfers, with a content-addressed cache so unchanged files are never re-sent
- [ ] Control channel: agent opens an outbound connection to a control server (WebSocket or gRPC over TLS), so no port forwarding is needed
- [ ] Encrypted overlay network (WireGuard, or Tailscale/Headscale) for direct machine-to-machine traffic
- [ ] NAT traversal (ICE with STUN and TURN, or QUIC) and LAN discovery (mDNS)
- [ ] Authentication: pairing with a one-time code, per-device keys, mTLS
- [ ] Log streaming with back-pressure, plus timeouts and reconnection
- [ ] Measure transfer time against compute time to decide when offloading is worth it

**Done when:** two machines on different home networks exchange a job, its logs, and its results with no port forwarding, over encrypted connections.

---

## Phase 4: Target depackaging (unpack and run on the target)

**Goal:** The target machine verifies, unpacks, runs, and cleans up any package safely.

- [ ] Verify before use: digest check, and a signature check if the sender signs packages
- [ ] Unpack by package type:
  - [ ] Linux target: `docker load` or pull, then `docker run`
  - [ ] Windows target: Windows container, or unzip a native bundle into a temporary folder
  - [ ] macOS target: Linux VM plus container, macOS VM image, or native bundle in a temporary account
- [ ] Prepare the run: temporary input and output folders mapped to `/data/in` and `/data/out` (or `{in}` and `{out}` for native packages), arguments, environment
- [ ] Resource limits: `--cpus`, `--memory`, `--init`, `--network none` for containers; Job Objects on Windows; equivalent limits on macOS
- [ ] Run, stream logs, enforce the time limit, and stop the whole process tree on cancel
- [ ] Collect outputs and report the exit code
- [ ] Clean up: containers, temporary folders, and an image-cache size policy
- [ ] Idle and battery rules for laptops (run only when idle, pause on battery)

**Done when:** the same job runs on a Linux, a Windows, and a Mac target, returns its outputs, and leaves each machine clean.

---

## Phase 5: Machine registry and matcher

**Goal:** Choose where a workload runs, manually or automatically.

- [ ] Machine registry (OS, architecture, RAM, GPU, supported package types, cost)
- [ ] Compatibility check using the Phase 1 table, with clear rejection messages
- [ ] `--on <machine>` for manual choice
- [ ] `--auto` for the cheapest compatible machine (own machines cost 0)
- [ ] Estimated cost before the run, actual cost after

## Phase 6: Reliability and safety

- [ ] Heartbeats, timeouts, and safe retry on another machine
- [ ] Folder access limited to one chosen folder, with a read-only option, snapshot before a run, and trash instead of delete
- [ ] Container hardening (read-only root filesystem, dropped privileges)

## Phase 7: Cloud machines

- [ ] Provision and destroy VMs on one provider, then add a second
- [ ] Pricing lookups (including spot prices), per-second usage tracking, and idle shutdown
- [ ] Spending limits
- [ ] Mac mini hosts, after checking cost and minimum rental periods

## Phase 8: Multi-user and security

- [ ] Accounts, quotas, and metering
- [ ] Stronger sandboxing (gVisor or Firecracker) and abuse detection
- [ ] Secrets handling

## Phase 9 (optional): Interactive apps

- [ ] Display streaming (Xpra, Sunshine/Moonlight, NICE DCV, WebRTC)
- [ ] Mount and hybrid file-access modes
- [ ] Licensing review for hosted use

---

## Out of scope

- Splitting one workload across several machines
- Moving part of a running program to another machine
- Several apps in one image
- Full virtual desktops
- Renting out machines to strangers
- Enterprise features (SSO, compliance certifications)

## Open questions

- Which package type should Windows apps use first: container, native bundle, or VM image?
- Should macOS apps run in a VM image or natively in a temporary account?
- Is bash good enough for the Windows targets, or does the target side need a small agent program sooner?
- How should packages be signed and verified between machines that do not trust a central server?
- How large can inputs be before transfer time defeats the purpose?
