## Setup

### 1. Create docker network

```bash
docker network create local
docker volume create --name infra-keycloak-db
docker volume create --name infra-kestra-db
docker volume create --name infra-kestra-data
docker volume create --name infra-backstage-db
docker volume create --name infra-clickhouse-data
docker volume create --name infra-rustfs-data
```

### 2. Generate TLS certificates

```bash
mkcert -install
mkcert -cert-file certs/localhost.pem -key-file certs/localhost-key.pem  localhost "*.localtest.me" 127.0.0.1 ::1
```

## Clone dependency repositories

```bash
git clone --depth 1 https://github.com/supabase/supabase
```

### 3. Start all services

```bash
docker compose up -d
```

Terraform による Keycloak のプロビジョニング手順と手動 `terraform plan`
の前提値は [terraform/README.md](terraform/README.md) にまとめています。

### 4. Access services

| Service         | URL                           |
| --------------- | ----------------------------- |
| Keycloak        | https://keycloak.localtest.me |
| Supabase API    | https://supabase.localtest.me |
| Supabase Studio | https://studio.localtest.me   |

### Default credentials

| Service         | Username | Password |
| --------------- | -------- | -------- |
| Keycloak        | admin    | admin    |
| Supabase Studio | supabase | supabase |

Credentials can be changed in `.env`.
