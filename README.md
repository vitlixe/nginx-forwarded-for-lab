# Nginx Forwarded For Lab

Test stand for checking safe `X-Forwarded-For` propagation through a chain of
nginx reverse proxies.

The stand contains three nginx instances and a small HTTP app. A request can
enter through any nginx and can also pass through several nginx instances before
reaching the app. The app prints the received request as JSON, including the
final `X-Forwarded-For` header.

## Requirements Covered

- The app receives the client address and all nginx hops in order.
- A spoofed `X-Forwarded-For` sent by the client is discarded.
- The setup is runnable with Docker Compose.
- The behavior is verifiable with `curl`.

## Project Structure

```text
.
├── docker-compose.yml    # Docker Compose topology and static IPs
├── Makefile              # convenience commands
├── README.md
├── app/
│   ├── Dockerfile
│   ├── go.mod
│   └── main.go           # HTTP app returning request data as JSON
├── nginx/
│   ├── nginx1.conf       # nginx1 routes
│   ├── nginx2.conf       # nginx2 routes
│   ├── nginx3.conf       # nginx3 routes
│   └── xff.conf          # shared trust and X-Forwarded-For logic
└── tests/
    └── test.sh           # curl-based verification script
```

## Services

| Service | Container IP | Host port |
|---------|--------------|-----------|
| nginx1  | 172.30.0.11  | 8081      |
| nginx2  | 172.30.0.12  | 8082      |
| nginx3  | 172.30.0.13  | 8083      |
| app     | 172.30.0.20  | -         |

## Routes

| URL                                   | Request path                         |
|---------------------------------------|--------------------------------------|
| `http://localhost:8081/app`           | client -> nginx1 -> app              |
| `http://localhost:8082/app`           | client -> nginx2 -> app              |
| `http://localhost:8083/app`           | client -> nginx3 -> app              |
| `http://localhost:8081/via-nginx2`    | client -> nginx1 -> nginx2 -> app    |
| `http://localhost:8081/via-nginx2-nginx3` | client -> nginx1 -> nginx2 -> nginx3 -> app |
| `http://localhost:8082/via-nginx3`    | client -> nginx2 -> nginx3 -> app    |

## Quick Start

```bash
make up
```

Or without Make:

```bash
docker compose up --build -d
```

## Make Targets

Build and start the lab:

```bash
make up
```

Run the automated curl-based checks:

```bash
make test
```

Follow container logs:

```bash
make logs
```

Stop and remove containers:

```bash
make down
```

## X-Forwarded-For Logic

The same logic is used by all nginx instances in `nginx/xff.conf`.

Only these exact nginx IPs are trusted:

```text
172.30.0.11
172.30.0.12
172.30.0.13
```

If the immediate peer is trusted, nginx preserves the incoming
`X-Forwarded-For` chain. If the peer is not trusted, nginx discards the incoming
header and starts a new chain from the real peer address.

Each nginx then appends its own `$server_addr`, so the app receives:

```text
client, nginx1, nginx2, nginx3
```

for a full `nginx1 -> nginx2 -> nginx3` path.

This is the important part: the Docker subnet is not trusted as a whole. Only
the known nginx container IPs are trusted.

## Test Protocol

The examples use `jq` only for readable output.

### Direct Requests

```bash
curl -s http://localhost:8081/app | jq
curl -s http://localhost:8082/app | jq
curl -s http://localhost:8083/app | jq
```

Expected `x_forwarded_for` format:

```text
<client-or-docker-gateway>, <nginx-ip>
```

Example:

```text
192.168.65.1, 172.30.0.11
```

On native Linux the first address is often `172.30.0.1` instead of
`192.168.65.1`.

### Chained Requests

```bash
curl -s http://localhost:8081/via-nginx2 | jq
curl -s http://localhost:8081/via-nginx2-nginx3 | jq
curl -s http://localhost:8082/via-nginx3 | jq
```

Expected examples:

```text
192.168.65.1, 172.30.0.11, 172.30.0.12
192.168.65.1, 172.30.0.11, 172.30.0.12, 172.30.0.13
192.168.65.1, 172.30.0.12, 172.30.0.13
```

### Spoofing Check

```bash
curl -s -H 'X-Forwarded-For: 1.2.3.4, 5.6.7.8' http://localhost:8081/app | jq
curl -s -H 'X-Forwarded-For: 1.2.3.4, 5.6.7.8' http://localhost:8081/via-nginx2-nginx3 | jq
```

Expected result: `x_forwarded_for` does not contain `1.2.3.4` or `5.6.7.8`.
