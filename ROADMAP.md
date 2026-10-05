# Poltergeist Roadmap

This roadmap is ordered so that each phase produces something that works and can be demonstrated. Later phases depend on earlier ones. Dates are intentionally left out until the first prototype shows how long things really take.

**Legend:** `[ ]` not started, `[~]` in progress, `[x]` done

---

## Phase 0: Research and design

**Goal:** Know exactly what to build first and what it costs.

- [ ] Define the first supported workload (for example: compile and run C/C++ jobs)
- [ ] Compare candidate cloud providers on price, API quality, and boot time
- [ ] Choose the CLI language (Go or Python)
- [ ] Sketch the job format (command, inputs, outputs, resource needs)
- [ ] Review Bazel's Remote Execution API as a reference for caching and job design
- [ ] Write a short threat model (what can a malicious job try to do?)

**Done when:** a one-page design document exists and the Phase 1 scope is agreed.

---

## Phase 1: Minimal prototype

**Goal:** Run one command on one cloud VM from the terminal.

- [ ] CLI command: `poltergeist run <command>`
- [ ] Manually created VM on one provider (AWS or Azure)
- [ ] Connect over SSH and sync files with rsync
- [ ] Stream stdout and stderr back live
- [ ] Download output files after the job finishes

**Done when:** a C/C++ project compiles on the remote VM and the binary comes back to your laptop with one command.

---

## Phase 2: Automation

**Goal:** Remove the manual steps and stop paying for idle machines.

- [ ] Small control-plane API (create job, check status, cancel)
- [ ] VM agent that receives and runs jobs
- [ ] Automatic VM creation and destruction through the cloud SDK
- [ ] Idle auto-shutdown and a hard maximum job duration
- [ ] Basic logging of job history

**Done when:** you run a command with no pre-existing VM, and the VM is created and destroyed automatically.

---

## Phase 3: Containers and caching

**Goal:** Make jobs reproducible and fast to repeat.

- [ ] Run jobs inside Docker/OCI containers
- [ ] Capture or define the job environment (image, dependencies)
- [ ] Content-addressed file cache (hash files, upload only what changed)
- [ ] Result caching for identical jobs
- [ ] Measure upload and download time against compute time

**Done when:** a second run of the same job is clearly faster than the first, and the environment matches between runs.

---

## Phase 4: Multi-cloud and price-based scheduling

**Goal:** The core differentiator: automatically use the cheapest machine.

- [ ] Add a second cloud provider behind a common interface
- [ ] Fetch current prices (including spot or preemptible options)
- [ ] Scheduler picks the cheapest machine meeting CPU, RAM, and GPU needs
- [ ] Fall back to another provider if one has no capacity
- [ ] Show an estimated cost before the job and the actual cost after

**Done when:** the same job runs on different providers depending on price, and the CLI reports the cost.

---

## Phase 5: Mac mini support

**Goal:** Serve macOS-only workloads.

- [ ] Evaluate hosts (AWS EC2 Mac, MacStadium, Scaleway, self-hosted minis)
- [ ] Work out a billing model given host minimums (for example AWS's 24-hour minimum)
- [ ] Consider a shared warm pool of Macs to enable per-second billing
- [ ] Follow Apple's license terms (macOS on Apple hardware, 2 VMs per Mac)
- [ ] Support a macOS build job end to end

**Done when:** a macOS-only build runs from the same CLI with an honest cost report.

---

## Phase 6: Multi-user, billing, and security

**Goal:** Safe for people other than the developer to use.

- [ ] User accounts and login (OAuth2/OIDC)
- [ ] Per-user quotas and spending limits
- [ ] Sandboxing with gVisor or Firecracker
- [ ] Network egress limits and abuse detection (for example crypto mining)
- [ ] Per-second usage metering and billing
- [ ] Secrets handling and encrypted storage

**Done when:** two separate users can run jobs at the same time without seeing each other's data, and usage is metered correctly.

---

## Phase 7 (optional): Interactive app streaming

**Goal:** Support GUI apps, only if earlier phases succeed and users ask for it.

- [ ] Choose a streaming approach (Xpra, Sunshine/Moonlight, NICE DCV, WebRTC)
- [ ] Prototype a single Linux GUI app streamed to the user
- [ ] Measure latency from the user's region
- [ ] Review Windows and software licensing before supporting those apps
- [ ] Decide whether this belongs in this project or a separate one

**Done when:** one GUI app is usable over the network with acceptable latency, and licensing is understood.

---

## Out of scope for now

- Full virtual desktops
- Running arbitrary interactive apps on day one
- Transparent offloading of part of a running program (for example GPU call forwarding)
- Enterprise features such as SSO directories and compliance certifications

## Open questions

- Which workload gives the clearest demo of savings: compiling, rendering, or ML training?
- How large can inputs be before data transfer defeats the purpose?
- Is a marketplace of spare consumer hardware worth the trust and security cost?
- What price per second leaves enough margin after provider costs?
