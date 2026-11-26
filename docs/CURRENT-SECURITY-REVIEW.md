# Current vulnerability and dependency review — dev17

Source: operator-supplied native `rescan-amd64` and `rescan-arm64` artifacts,
Trivy 0.70.0, Debian 13.8, 2026-11-26. Same published manifest:
`sha256:03bbffadba60a562651a2078c3d20325d5c62d86f0efebf8ebe35bd939983724`.
The two inventories contain 101 packages each. The 324 findings per image
match on ID, binary package, installed version, severity, status and fixed
version. 148 distinct IDs, 76 HIGH occurrences (25 IDs), 132 MEDIUM, 96 LOW,
20 UNKNOWN, zero CRITICAL and no fix version reported. No Unbound package
finding. This is a dated scan, not a guarantee of current or future safety.
No exception is added; all individual risk dispositions remain open pending
actual runtime audit and operator approval.

## Individual HIGH triage

Advisory summaries below are derived from supplied Trivy descriptions.
Mitigations are configuration-based hypotheses, not a VEX or a claim of
non-exploitability. Follow the tracker links and re-review exact versions
before approving a deployment.

| CVE | Installed binary packages (version) | Reported issue | Preliminary applicability |
|---|---|---|---|
| [CVE-2025-69720](https://security-tracker.debian.org/tracker/CVE-2025-69720) | libncursesw6, libtinfo6, ncurses-base, ncurses-bin (`6.5+20250216-2`) | Terminal buffer overflow | No interactive terminal or ncurses UI in daemon; verify linked tools. |
| [CVE-2026-0799](https://security-tracker.debian.org/tracker/CVE-2026-0799) | libpcap0.8t64 (`1.10.5-2`) | Packet/BPF out-of-bounds access | libpcap only required by ldnsutils in scan graph; no capture operation configured. |
| [CVE-2026-107494](https://security-tracker.debian.org/tracker/CVE-2026-107494) | libssl3t64, openssl, openssl-provider-legacy (`3.5.9-1~deb13u1`) | QUIC frame queue growth | No QUIC listener/configuration; OpenSSL is nonetheless linked for DNSSEC. |
| [CVE-2026-10846](https://security-tracker.debian.org/tracker/CVE-2026-10846) | ldnsutils, libldns3t64 (`1.8.4-2+b1`) | UDP stub response matching | Relevant to drill UDP liveness and diagnostics; loopback synthetic record, not general recursion; retain TCP option and monitor fixed Debian package. |
| [CVE-2026-113351](https://security-tracker.debian.org/tracker/CVE-2026-113351) | libexpat1 (`2.9.0-1~deb13u1`) | XML parser reset memory tracking | Expat installed via libpython; no Python or XML module configured. |
| [CVE-2026-115506](https://security-tracker.debian.org/tracker/CVE-2026-115506) | libexpat1 (`2.9.0-1~deb13u1`) | XML entity amplification | No XML parsing configured; confirm actual library/module reachability. |
| [CVE-2026-117610](https://security-tracker.debian.org/tracker/CVE-2026-117610) | libexpat1 (`2.9.0-1~deb13u1`) | External entity parser null dereference | No XML input configured; confirm actual library/module reachability. |
| [CVE-2026-118370](https://security-tracker.debian.org/tracker/CVE-2026-118370) | libexpat1 (`2.9.0-1~deb13u1`) | XML attribute integer overflow | No XML input configured; confirm actual library/module reachability. |
| [CVE-2026-119373](https://security-tracker.debian.org/tracker/CVE-2026-119373) | libsqlite3-0 (`3.46.1-7+deb13u2`) | FTS5 heap overflow | No FTS5 or SQLite input configured; SQLite also required by liblastlog2-2. |
| [CVE-2026-119374](https://security-tracker.debian.org/tracker/CVE-2026-119374) | libsqlite3-0 (`3.46.1-7+deb13u2`) | Corrupt FTS5 index | No FTS5 database configured; verify actual use. |
| [CVE-2026-119379](https://security-tracker.debian.org/tracker/CVE-2026-119379) | libsqlite3-0 (`3.46.1-7+deb13u2`) | Crafted SQLite session changesets | No changeset ingestion configured; verify actual use. |
| [CVE-2026-124709](https://security-tracker.debian.org/tracker/CVE-2026-124709) | libssl3t64, openssl, openssl-provider-legacy (`3.5.9-1~deb13u1`) | QUIC stream memory leak | No QUIC listener/configuration; track Debian OpenSSL update. |
| [CVE-2026-15308](https://security-tracker.debian.org/tracker/CVE-2026-15308) | libpython3.13, libpython3.13-minimal, libpython3.13-stdlib (`3.13.5-2+deb13u5`) | HTML parser CPU denial of service | Python library required by Debian Unbound, no Python module in configured module chain. |
| [CVE-2026-16742](https://security-tracker.debian.org/tracker/CVE-2026-16742) | libsystemd0, libudev1 (`257.13-1~deb13u1`) | systemd-homed local privilege escalation | No systemd-homed executable listed in either package inventory; non-root process. |
| [CVE-2026-19445](https://security-tracker.debian.org/tracker/CVE-2026-19445) | libpython3.13, libpython3.13-minimal, libpython3.13-stdlib (`3.13.5-2+deb13u5`) | Python TLS SNI callback use-after-free | No Python TLS callbacks configured. |
| [CVE-2026-19553](https://security-tracker.debian.org/tracker/CVE-2026-19553) | libpython3.13, libpython3.13-minimal, libpython3.13-stdlib (`3.13.5-2+deb13u5`) | Python SSLContext hostname verification | No Python TLS client configured. |
| [CVE-2026-54369](https://security-tracker.debian.org/tracker/CVE-2026-54369) | libacl1 (`2.3.2-2+b1`) | ACL symlink traversal privilege escalation | Non-root, no capabilities, read-only root; review dedicated writable state and host permissions. |
| [CVE-2026-6554](https://security-tracker.debian.org/tracker/CVE-2026-6554) | libpcap0.8t64 (`1.10.5-2`) | BPF interpreter denial of service | No packet-capture or user BPF input in DNS service. |
| [CVE-2026-7210](https://security-tracker.debian.org/tracker/CVE-2026-7210) | libpython3.13, libpython3.13-minimal, libpython3.13-stdlib (`3.13.5-2+deb13u5`) | Python/Expat XML denial of service | No Python or XML input configured. |
| [CVE-2026-76642](https://security-tracker.debian.org/tracker/CVE-2026-76642) | bsdutils (`1:2.41.5-0+deb13u1`); libblkid1, liblastlog2-2, libmount1, libsmartcols1, libuuid1, mount, util-linux (`2.41.5-0+deb13u1`); login (`1:4.16.0-2+really2.41.5-0+deb13u1`) | Mount helper privileged post-hooks | No mount operation in daemon; no capabilities and no privilege escalation. |
| [CVE-2026-78408](https://security-tracker.debian.org/tracker/CVE-2026-78408) | bsdutils (`1:2.41.5-0+deb13u1`); libblkid1, liblastlog2-2, libmount1, libsmartcols1, libuuid1, mount, util-linux (`2.41.5-0+deb13u1`); login (`1:4.16.0-2+really2.41.5-0+deb13u1`) | nsenter cgroup migration authority | No namespace entry in daemon; no privileged container or Docker socket. |
| [CVE-2026-78409](https://security-tracker.debian.org/tracker/CVE-2026-78409) | bsdutils (`1:2.41.5-0+deb13u1`); libblkid1, liblastlog2-2, libmount1, libsmartcols1, libuuid1, mount, util-linux (`2.41.5-0+deb13u1`); login (`1:4.16.0-2+really2.41.5-0+deb13u1`) | Detached mount tree symlink escape | No mount operation; review host mount configuration independently. |
| [CVE-2026-78410](https://security-tracker.debian.org/tracker/CVE-2026-78410) | bsdutils (`1:2.41.5-0+deb13u1`); libblkid1, liblastlog2-2, libmount1, libsmartcols1, libuuid1, mount, util-linux (`2.41.5-0+deb13u1`); login (`1:4.16.0-2+really2.41.5-0+deb13u1`) | Restricted bind mount source redirection | No mount operation; review host bind source and ownership independently. |
| [CVE-2026-82049](https://security-tracker.debian.org/tracker/CVE-2026-82049) | libpython3.13, libpython3.13-minimal, libpython3.13-stdlib (`3.13.5-2+deb13u5`) | Python tarfile file modification/disclosure | No archive ingestion in daemon. |
| [CVE-2026-9538](https://security-tracker.debian.org/tracker/CVE-2026-9538) | perl-base (`5.40.1-6+deb13u1`) | Archive::Tar allocation denial of service | No Archive/Tar file listed in either inventory and no archive ingestion in daemon; confirm package contents. |

## Installed dependency evidence

Both scans contain `DependsOn` and installed-file inventories. The following
paths are present in the AMD64 package graph and the corresponding packages
are installed on ARM64. Runtime linkage still needs independent verification.

- `unbound` -> `libpython3.13` -> `libexpat1`, `libpython3.13-stdlib`.
- `libpython3.13-stdlib` -> `libsqlite3-0`, `libpython3.13-minimal`, ncurses.
- `liblastlog2-2` also requires `libsqlite3-0`; removing Python alone would not remove it.
- `ldnsutils` -> `libldns3t64` and `libpcap0.8t64`; no other reverse dependency is listed for either library in the AMD64 graph.
- Neither inventory lists BIND, LMDB or libxml2 packages, `Archive/Tar` files, `/usr/bin/python*` executables or `systemd-homed`. This is package-file evidence, not proof of absence of every possible runtime file.

## Decision: retain drill for 0.1.0

Dev8 deliberately replaced dig/BIND after three unfixed LMDB CRITICAL
findings and one libxml2 CRITICAL finding blocked dev7. ARM64 local image
size dropped from 152,544,990 to 142,298,403 bytes. The existing package
guard prevents these dependencies from returning. The current LDNS issue
does not justify automatically reverting this decision. Keep Debian
packages, the current loopback healthcheck and the unchanged security gate.

| Alternative | Assessment |
|---|---|
| Keep Debian ldnsutils | Current baseline; one LDNS HIGH ID, two package findings; no new dependencies. |
| Prefer TCP for selected probes | Avoids the specific UDP matching path; does not remove packages or replace UDP liveness coverage. |
| unbound-control status | Existing tool, but checks control-plane liveness rather than real UDP/TCP DNS answers. Not an equivalent healthcheck. |
| Custom Perl or C DNS probe | Needs new runtime or build/maintenance surface and careful DNS parsing; compare actual dependencies and negative tests first. |
| Restore dig | Rejected until a separate reviewed candidate proves it does not reintroduce the excluded BIND/LMDB/libxml2 dependencies. |

Removing ldnsutils could remove at least the two LDNS and two libpcap HIGH
occurrences if those packages disappear, but this is a hypothetical
candidate, not a measured reduction. Do not remove essential libraries
by hand or mix unstable packages into Debian stable. The new read-only
runtime audit records exact image ID, installed dependency fields, `ldd`,
effective module configuration and a simulated APT removal. It never removes
anything. A future candidate needs UDP/TCP health, DNSSEC, integration, both
native builds, size and scan comparison before adoption.

See [historical review](VULNERABILITY-REVIEW.md), [policy](../security/README.md),
[release checklist](RELEASE-CHECKLIST.md).
