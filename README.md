# Project-Poltergeist

CaaS (Compute as services)
On-demand app streaming and execution across clouds

Hardware keeps getting more expensive, but most people only need powerful
machines for a few hours at a time. Poltergeist lets you run any app on a
cloud VM (AWS ECS/EC2, Azure VM, or even a Mac mini) straight from your
terminal.

```bash
poltergeist connect
poltergeist launch /path/to/app
```

## Goals
- Run any type of app: CLI tools, GUI apps, and macOS-only software
- Pick the cheapest available machine across cloud providers
- Per-second billing with no long minimum commitments
- Simple enough for students and hobbyists

## Status
Early planning and prototyping.

