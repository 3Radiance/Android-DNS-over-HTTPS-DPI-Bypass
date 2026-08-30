# Android DNS-over-HTTPS + DPI Bypass

**[Читать на русском →](./README_RU.md)**

Scripts for automatic DNS-over-HTTPS and DPI bypass on Android via Magisk/KernelSU.

## What it does

| Script | Purpose |
|--------|---------|
| `99-doh.sh` | Intercepts DNS queries (port 53) and routes them through DoH (Google DNS) |
| `99-nfqws.sh` | Bypasses DPI for V2RayNG traffic via nfqws (fake packets, fragmentation) |

## Requirements

- **Root** (Magisk/KernelSU)
- **Binaries** in `/data/local/tmp/`:
  - `doh-stub-rust` — DoH resolver
  - `nfqws` — from `nfqws_custom` module
- **V2RayNG** (`com.v2ray.ang.fdroid`) installed and running
- **Host list** `/data/local/tmp/hosts.txt` for nfqws

## Installation

```bash
# Copy to service.d (Magisk/KernelSU)
cp 99-doh.sh /data/adb/service.d/
cp 99-nfqws.sh /data/adb/service.d/
chmod +x /data/adb/service.d/*.sh
```

## Configuration

### 99-doh.sh

| Variable | Default | Description |
|----------|---------|-------------|
| `DOH_BIN` | `/data/local/tmp/doh-stub-rust` | Path to DoH binary |
| `LISTEN_PORT` | `5300` | Local DNS port |
| `NOBODY_UID` | `9999` | UID to run doh-stub as |
| `LD_LIBRARY_PATH` | `/data/local/tmp` | Library path |
| `LOG_FILE` | `/data/local/tmp/dns_log.log` | Log file path |

### 99-nfqws.sh

| Variable | Default | Description |
|----------|---------|-------------|
| `NFQWS_DIR` | `/data/adb/modules/nfqws_custom` | Path to nfqws module |
| `NFQWS_BIN` | `$NFQWS_DIR/nfqws` | Path to nfqws binary |
| `HOST_LIST` | `/data/local/tmp/hosts.txt` | Host list for bypass |
| `QNUM` | `300` | NFQUEUE number |

## How it works

### DoH (`99-doh.sh`)

1. Waits for boot completion (`sys.boot_completed`)
2. Disables IPv6 (to prevent DNS leaks)
3. Starts `doh-stub-rust` on port 5300
4. Redirects UDP/TCP 53 → 5300 via `iptables nat`
5. Loop with check every 10 seconds

### DPI Bypass (`99-nfqws.sh`)

1. Waits for boot completion (`sys.boot_completed`)
2. Gets V2RayNG UID from system (`pm list packages -U`)
3. Whitelists `nobody` traffic (to prevent loops)
4. Routes V2RayNG HTTP/HTTPS to NFQUEUE 300
5. `nfqws` fragments packets and spoofs SNI (`cloudflare.com`)
6. Loop with check every 10 seconds

## nfqws Parameters

| Parameter | Description |
|-----------|-------------|
| `--dpi-desync=fake,multisplit` | Desync type: fake packets + multisplit |
| `--dpi-desync-split-seqovl=345` | SEQ overlap size |
| `--dpi-desync-split-pos=1` | Split position |
| `--dpi-desync-fooling=ts` | Fooling via TCP timestamps |
| `--dpi-desync-repeats=4` | Number of fake repeats |
| `--dpi-desync-fake-tls-mod=rnd,dupsid,sni=cloudflare.com` | TLS modification: random data, duplicate SID, fake SNI |

## Logs

| File | Description |
|------|-------------|
| `/data/local/tmp/dns_log.log` | DoH resolver logs |
| `/data/local/tmp/nfqws_log.log` | nfqws logs |

## Checking Status

```bash
# Check if DoH is listening
netstat -tlnp | grep 5300

# Check iptables rules
iptables -t nat -L OUTPUT -n -v
iptables -t mangle -L OUTPUT -n -v

# Check processes
ps | grep doh-stub
ps | grep nfqws

# Check DNS
getprop net.dns1
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| DNS not working | `doh-stub-rust` not running | Check `LD_LIBRARY_PATH`, logs |
| Sites not loading | nfqws not catching packets | Check V2Ray UID, `iptables -t mangle` |
| Battery drain | `sleep` interval too short | Increase loop interval |
| DNS leaking via IPv6 | IPv6 not disabled | Check `/proc/sys/net/ipv6/conf/*/disable_ipv6` |

## File Structure

```
/data/local/tmp/
├── doh-stub-rust          # DoH binary
├── dns_log.log            # DNS logs
├── nfqws_log.log          # nfqws logs
└── hosts.txt              # Host list for bypass

/data/adb/modules/nfqws_custom/
└── nfqws                  # nfqws binary

/data/adb/service.d/
├── 99-doh.sh              # DoH script
└── 99-nfqws.sh            # DPI bypass script
```

## Security

- DoH resolver runs as `nobody` (UID 9999) for isolation
- `nobody` traffic is excluded from redirection (loop prevention)
- IPv6 is forcibly disabled to prevent DNS leaks
