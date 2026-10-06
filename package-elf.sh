
#!/usr/bin/env bash
# Package one Linux ELF executable with Docker Buildx.
# Requires: bash, docker with buildx, readelf (binutils), file, cp, mktemp.
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: package-elf.sh ELF_PATH [options]

Options:
  -t, --tag NAME          Resulting image tag (default: elf-app)
  -p, --platform PLATFORM Override detected platform, e.g. linux/arm64
  -e, --extra-dir DIR     Copy extra files into the final rootfs. Preserve
                          absolute layout: DIR/etc/x becomes /etc/x.
      --include-nss        Bundle NSS modules and nsswitch.conf (recommended
                          for static glibc programs resolving names/users).
      --builder-image IMG  Override automatic Debian/Alpine builder choice.
      --trace              Run the resulting image under strace after building
                          and save loaded shared-object paths in a new
                          elf-runtime-trace.* directory. Place application
                          arguments after --, e.g. --trace -- --serve 8080.
      --trace-network NET  Docker network for the trace (default: none).
  -h, --help              Show this help.

The ELF may be anywhere on the host: this script copies it into a temporary
Docker build context. It builds one target platform and loads it locally.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'warning: %s\n' "$*" >&2; }

[[ $# -gt 0 ]] || { usage; exit 2; }
elf=$1
shift
tag=elf-app
platform=''
extra_dir=''
include_nss=0
builder_image=''
trace=0
trace_network=none
trace_args=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -t|--tag) tag=${2:?"$1 needs a value"}; shift 2 ;;
    -p|--platform) platform=${2:?"$1 needs a value"}; shift 2 ;;
    -e|--extra-dir) extra_dir=${2:?"$1 needs a value"}; shift 2 ;;
    --include-nss) include_nss=1; shift ;;
    --builder-image) builder_image=${2:?"$1 needs a value"}; shift 2 ;;
    --trace) trace=1; shift ;;
    --trace-network) trace_network=${2:?"$1 needs a value"}; shift 2 ;;
    --)
      shift
      trace_args=("$@")
      break
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

for command in docker readelf file awk sort cp mktemp; do
  command -v "$command" >/dev/null || die "required command not found: $command"
done
[[ -f $elf ]] || die "not a regular file: $elf"
[[ -r $elf ]] || die "cannot read: $elf"
[[ -z $extra_dir || -d $extra_dir ]] || die "extra directory does not exist: $extra_dir"

# readelf only parses bytes; unlike ldd it does not invoke the supplied binary.
readelf -h "$elf" >/dev/null 2>&1 || die "not an ELF file: $elf"
elf_type=$(readelf -h "$elf" | awk -F: '/Type:/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')
machine=$(readelf -h "$elf" | awk -F: '/Machine:/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')
interpreter=$(readelf -l "$elf" | awk '/Requesting program interpreter/ {gsub(/\[|\]/, "", $NF); print $NF; exit}')

case $machine in
  'Advanced Micro Devices X86-64') detected_platform=linux/amd64 ;;
  AArch64) detected_platform=linux/arm64 ;;
  ARM) detected_platform=linux/arm/v7 ;;
  'IBM S/390') detected_platform=linux/s390x ;;
  'RISC-V') detected_platform=linux/riscv64 ;;
  *) die "unsupported/unknown ELF architecture: $machine (pass --platform after extending this script)" ;;
esac
[[ -n $platform ]] || platform=$detected_platform

case $elf_type in
  EXEC*) ;;
  DYN*)
    [[ -n $interpreter ]] || warn 'ET_DYN without an interpreter looks like a shared library, not a directly runnable executable.'
    ;;
  *) warn "ELF type is '$elf_type', not a normal executable." ;;
esac
[[ -x $elf ]] || warn 'file is not executable on the host; the image will set its executable bit.'

if [[ -z $interpreter ]]; then
  libc=static
  printf 'Detected static ELF (%s, %s).\n' "$machine" "$elf_type"
elif [[ $interpreter == *ld-musl-* ]]; then
  libc=musl
  printf 'Detected dynamically linked musl ELF: %s\n' "$interpreter"
  [[ -n $builder_image ]] || builder_image=alpine:3.20
elif [[ $interpreter == *ld-linux* || $interpreter == *ld64.so* ]]; then
  libc=glibc
  printf 'Detected dynamically linked glibc ELF: %s\n' "$interpreter"
  glibc_requirement=$(readelf --version-info "$elf" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sed 's/GLIBC_//' | sort -V | tail -n 1 || true)
  if [[ -n $glibc_requirement ]]; then
    printf 'Maximum required GLIBC symbol version: %s\n' "$glibc_requirement"
    # Bookworm ships glibc 2.36.  Use unstable only when an ELF demands newer;
    # callers can pin a tested base using --builder-image.
    if [[ $(printf '%s\n%s\n' 2.36 "$glibc_requirement" | sort -V | tail -n 1) != 2.36 ]]; then
      warn "requires glibc $glibc_requirement, newer than Bookworm's 2.36; selecting Debian unstable. Pin --builder-image after testing."
      [[ -n $builder_image ]] || builder_image=debian:unstable-slim
    fi
  fi
else
  libc=unknown
  warn "unrecognised ELF interpreter '$interpreter'; treating it as glibc-compatible. Override with --builder-image if needed."
fi

[[ -n $builder_image ]] || builder_image=debian:bookworm-slim
printf 'Target platform: %s\nBuilder image: %s\n' "$platform" "$builder_image"

if readelf -d "$elf" 2>/dev/null | grep -qE 'lib(cuda|nvidia|vulkan|OpenCL|drm)'; then
  warn 'hardware/accelerator library detected: the host driver, device access, and Docker runtime flags are still required.'
fi
if [[ $libc == static && $include_nss -eq 0 ]]; then
  warn 'static glibc programs that use DNS, users, or groups may need NSS; rerun with --include-nss and test name resolution.'
fi

context=$(mktemp -d)
cleanup() { rm -rf -- "$context"; }
trap cleanup EXIT
mkdir -p "$context/extra"
cp -- "$elf" "$context/app"
if [[ -n $extra_dir ]]; then
  cp -a -- "$extra_dir/." "$context/extra/"
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cp -- "$script_dir/Dockerfile" "$context/Dockerfile"

printf 'Bootstrapping Buildx (cross-platform builds need a builder with emulation).\n'
docker buildx inspect --bootstrap >/dev/null
docker buildx build --load \
  --platform "$platform" \
  --build-arg ELF_PATH=app \
  --build-arg BUILDER_IMAGE="$builder_image" \
  --build-arg INCLUDE_NSS="$include_nss" \
  --tag "$tag" \
  "$context"

printf 'Built %s for %s. Run: docker run --rm %s\n' "$tag" "$platform" "$tag"

if [[ $trace -eq 1 ]]; then
  trace_tag="${tag}-trace"
  trace_dir=$(mktemp -d "${PWD}/elf-runtime-trace.XXXXXX")
  printf 'Building diagnostic trace image and writing trace data to %s\n' "$trace_dir"
  docker buildx build --load \
    --target trace \
    --platform "$platform" \
    --build-arg ELF_PATH=app \
    --build-arg BUILDER_IMAGE="$builder_image" \
    --build-arg INCLUDE_NSS="$include_nss" \
    --tag "$trace_tag" \
    "$context"

  # A trace runs supplied code. Network is disabled by default; use
  # --trace-network only when the workload genuinely needs it.
  set +e
  docker run --rm --platform "$platform" --network "$trace_network" \
    --volume "${trace_dir}:/trace" "$trace_tag" "${trace_args[@]}"
  trace_status=$?
  set -e
  [[ $trace_status -eq 0 ]] || warn "traced workload exited with status $trace_status; partial results may still be useful."

  mapfile -d '' trace_files < <(find "$trace_dir" -type f -name 'files.*' -print0)
  manifest="$trace_dir/runtime-libraries.txt"
  if [[ ${#trace_files[@]} -gt 0 ]]; then
    awk '
      /= [0-9]+/ {
        line = $0
        while (match(line, /"[^"]+"/)) {
          path = substr(line, RSTART + 1, RLENGTH - 2)
          if (path ~ /\.so(\.[^\/"]*)?$/) print path
          line = substr(line, RSTART + RLENGTH)
        }
      }
    ' "${trace_files[@]}" | sort -u > "$manifest"
    printf 'Runtime shared-library manifest: %s\n' "$manifest"
  else
    warn "no strace files were produced; inspect $trace_dir and ensure the workload starts successfully."
  fi
fi
