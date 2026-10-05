# Poltergeist

> Run any heavy task on the cheapest available cloud machine, billed by the second, straight from your terminal.

**Status: early planning.** The commands and features below describe the intended design. Nothing here is implemented yet. See [ROADMAP.md](ROADMAP.md) for the plan.

---

## Why

Hardware (GPUs, RAM, Macs) keeps getting more expensive, but most people only need powerful machines for a few hours at a time. Buying hardware for occasional heavy work is wasteful, and the big cloud providers are built for companies: complex setup, confusing pricing, and long minimum commitments (for example, a 24-hour minimum for Mac instances on AWS).

Poltergeist lets you keep a cheap local computer and rent the heavy lifting only for the seconds you use it.

## What it does

You run a command. Poltergeist finds the cheapest suitable cloud machine, runs the job there, streams the logs back, brings the results home, and shuts the machine down.

```bash
# Planned usage
poltergeist run make -j64
poltergeist run python train.py --gpu
poltergeist run ffmpeg -i input.mp4 output.mp4
poltergeist run ./myapp --os macos
```

## How it works

```
CLI ──HTTPS/gRPC──> Control plane (auth, scheduler, billing)
                          |
                          v
                    Provisioner (cloud SDKs / Terraform)
                          |
                          v
              VM pool + agent ── runs the job in a sandboxed container
                          |
CLI <══ live logs & results ═╝
```

1. The CLI authenticates and submits the job.
2. The scheduler picks the cheapest machine that meets the job's needs (AWS, Azure, Mac mini hosts, and so on).
3. The provisioner starts a VM, or takes one from a warm pool.
4. Changed input files are synced, and the job runs in a container.
5. Logs stream back live and outputs are downloaded.
6. The machine shuts down and billing stops.

## Planned features

- One-command remote execution
- Cheapest-machine selection across cloud providers
- Per-second billing with no minimum commitments
- Incremental file sync and caching
- Live log streaming
- Automatic shutdown of idle machines
- Sandboxed execution of untrusted code
- Mac mini support for macOS-only workloads

## Who it is for

Students, hobbyists, and independent developers who need occasional heavy compute (compiling, rendering, video encoding, ML training, test suites, macOS builds) and do not want to buy hardware or learn cloud administration.

## What it is not

- **Not a virtual desktop.** You do not get a remote desktop. You send a job and get results.
- **Not for interactive GUI apps (yet).** Streaming a full interactive app is a possible later phase, not the starting goal.
- **Not guaranteed cheaper than owning hardware** for people who use heavy compute every day. The savings come from sharing machines across many short sessions.

## Existing tools and how this differs

Remote execution and cloud desktops already exist: AWS Batch, Modal, Bazel Remote Execution, GitHub Codespaces, Amazon WorkSpaces, Azure Virtual Desktop, Kasm, Parsec, and others. Poltergeist aims to differ by being:

- **Multi-cloud**, picking the cheapest provider for you
- **Per-second billed**, including for Mac minis
- **Terminal-first** and simple, like Docker or Heroku
- **Aimed at students and small developers**, a segment large providers do not serve well

## Tech stack (planned)

| Area | Choice |
|---|---|
| CLI | Go or Python |
| Control plane | gRPC or REST, OAuth2/OIDC login |
| File transfer | SSH, rsync/SFTP, S3-compatible storage |
| Packaging | Docker / OCI containers |
| Provisioning | Cloud SDKs or Terraform |
| Sandboxing | gVisor or Firecracker |
| Networking | WireGuard or Tailscale |

## Known challenges

- **Data transfer** can cancel out the speed benefit for large inputs, so caching is essential.
- **Environment mismatch** between local and cloud machines requires containers or dependency capture.
- **Security**: running arbitrary code needs strong sandboxing, quotas, and network limits.
- **Licensing**: macOS may only run on Apple hardware (limited to 2 VMs per Mac), and Windows has its own multi-user rules.
- **Thin margins** for a broker model; it depends on volume.

## Roadmap

See [ROADMAP.md](ROADMAP.md).

## Contributing

The project is at the idea stage. Feedback, design suggestions, and issues are welcome.

## License

To be decided.
