# narasim-n8n

Base template for self-hosted n8n with automatic bootstrap, secure credentials handling, and workflow management.

## Features

- **Auto Bootstrap** — automatic admin user creation on first start
- **Secure Credentials** — credentials imported via API and deleted from filesystem
- **Workflow Import** — automatic workflow import during bootstrap
- **SQLite/PostgreSQL** — supports both database types
- **Volume Persistence** — data stored in `./volumes/home/node`

## Quick Start

```bash
cp .env.example .env

# Generate encryption key and add to .env
openssl rand -hex 16

# Create bootstrap credentials file
cat > credentials/bootstrap.env << EOF
N8N_BOOTSTRAP_OWNER_EMAIL=admin@example.com
N8N_BOOTSTRAP_OWNER_PASSWORD=Admin123!
N8N_BOOTSTRAP_OWNER_FIRSTNAME=Admin
N8N_BOOTSTRAP_OWNER_LASTNAME=User
EOF

# Start with dev config (exposes port 5678)
docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build

# Access n8n UI
open http://localhost:5678
```

## Directory Structure

```
├── docker-compose.yml      # Main Docker configuration
├── docker-compose.dev.yml  # Dev overrides (port exposure)
├── Dockerfile              # Custom n8n image
├── entrypoint.sh           # Container entrypoint
├── .env.example            # Environment template
├── credentials/            # Credential JSON files (gitignored)
│   └── README.md           # Credentials format documentation
├── workflows/              # Workflow JSON files
├── scripts/
│   ├── bootstrap.sh        # Auto-setup script
│   └── workflow-sync.sh    # Import/export workflows
├── databases/              # Custom database migrations
├── tests/                  # Test scripts
└── volumes/
    └── home/node/          # Persistent data (mounted to /home/node)
```

## Bootstrap

On first start, if `credentials/bootstrap.env` file exists:

1. Loads admin credentials from `bootstrap.env`
2. Creates admin user via API
3. Imports credentials from `/tmp/credentials` (then deletes files)
4. Imports workflows from `/home/node/workflows`
5. Activates workflows (configurable via `N8N_BOOTSTRAP_ACTIVATE_WORKFLOWS`)
6. Deletes `bootstrap.env` — credentials never appear in container env
7. Creates `.bootstrapped` marker to prevent re-run

## Credentials

Place credential JSON files in `credentials/` folder:

```json
[
  {
    "id": "openrouter-cred",
    "name": "OpenRouter",
    "type": "openRouterApi",
    "data": { "apiKey": "sk-or-v1-..." }
  }
]
```

Files are copied to `/tmp/credentials` during build, imported via API, then **deleted** for security.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `N8N_ENCRYPTION_KEY` | Encryption key for credentials | Required |
| `N8N_PERSONALIZATION_ENABLED` | Show personalization survey | `false` |
| `N8N_BOOTSTRAP_ACTIVATE_WORKFLOWS` | Activate workflows: `true`/`all` or comma-separated names | `true` |
| `DB_TYPE` | Database type | `sqlite` |

### Bootstrap credentials (in `credentials/bootstrap.env`)

| Variable | Description |
|----------|-------------|
| `N8N_BOOTSTRAP_OWNER_EMAIL` | Admin email |
| `N8N_BOOTSTRAP_OWNER_PASSWORD` | Admin password (must contain number) |
| `N8N_BOOTSTRAP_OWNER_FIRSTNAME` | Admin first name |
| `N8N_BOOTSTRAP_OWNER_LASTNAME` | Admin last name |

## Workflow Management

```bash
# Import workflows
docker compose exec n8n sh /home/node/scripts/workflow-sync.sh import

# Export workflows
docker compose exec n8n sh /home/node/scripts/workflow-sync.sh export

# List workflows
docker compose exec n8n sh /home/node/scripts/workflow-sync.sh list
```

## Build Arguments

```bash
docker compose build --no-cache \
  --build-arg N8N_VERSION=2.1.1 \
  --build-arg NODE_VERSION=22.21.1
```

## References

- [n8n Documentation](https://docs.n8n.io/)
- [n8n MCP Server](https://docs.n8n.io/advanced-ai/accessing-n8n-mcp-server/)
