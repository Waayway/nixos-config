# VLAN & VMID Scheme

Subnet: `10.0.10.0/24`

**Rule: the IP's last octet is the VMID.** VMID 120 → `10.0.10.120`.

## Address bands

| Range | Use |
|---|---|
| `.1`–`.10` | Control devices — gateway, switch, AP, PVE host |
| `.11`–`.20` | DHCP pool — new / unknown devices |
| `.21`–`.99` | Static non-Proxmox hosts — NAS, printer, IoT |
| `.100`–`.254` | Proxmox guests |
| `.255` | Broadcast |

## 1xx — platform

Run for the lab itself.

| Block | Use |
|---|---|
| 100–109 | Core & personal compute |
| 110–119 | Network & remote access |
| 120–129 | Media |
| 130–139 | Home automation |
| 140–149 | Messaging & monitoring |
| 150–159 | Backup & data protection |
| 160–169 | Databases & middleware |
| 170–179 | Dev, build & CI |
| 180–189 | Sandbox / throwaway |
| 190–199 | Free |

## 2xx — shared workloads

Consumed by other people or other machines.

| Block | Use |
|---|---|
| 200–209 | Game servers |
| 210–219 | File & storage services |
| 220–229 | Web / public-facing |
| 230–254 | Free |

## 9000+ — templates

No IP, never running.

## Rules

- Ceiling is 254. A guest needing an IP here must be 100–254.
- Keep `x8` and `x9` free in every block for clones and test twins.
- Set Next Free VMID Range to 100–254 in Datacenter → Options.
