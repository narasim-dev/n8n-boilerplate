# n8n MCP Server Template

Standalone n8n server template with SQLite database for building MCP (Model Context Protocol) servers.

## Quick Start

```bash
# Copy environment file
cp .env.example .env

# Generate encryption key and update .env
openssl rand -hex 16

# Build and start n8n
docker compose up -d --build

# Access n8n UI
open http://localhost:5678
```

## Directory Structure

```
/
├── docker-compose.yml    # Docker configuration
├── Dockerfile            # Custom n8n image build
├── .env.example          # Environment variables template
├── data/                 # SQLite database (auto-created)
├── workflows/            # Workflow JSON files for sync
└── scripts/              # Workflow sync scripts
    └── workflow-sync.sh  # Import/export workflows
```

## Workflow Management

### Import workflows

```bash
docker compose exec n8n-container-name sh /data/scripts/workflow-sync.sh import
```

### Export workflows

```bash
docker compose exec n8n-container-name sh /data/scripts/workflow-sync.sh export
```

### List workflows

```bash
docker compose exec n8n-container-name sh /data/scripts/workflow-sync.sh list
```

## Image Build

This project builds a custom n8n image from npm (see `Dockerfile`) and installs extra CLI tools inside the container:

- **sqlite3**
- **curl**
- **jq**

To verify the effective version:

```bash
docker compose exec n8n n8n --version
```

To override versions during build:

```bash
docker compose build --no-cache \
  --build-arg N8N_VERSION=2.1.1 \
  --build-arg NODE_VERSION=22.21.1
```

## MCP Token Generation

To programmatically generate MCP access tokens, see the algorithm in `jwt.service.ts`:

```javascript
const crypto = require('crypto');
const jwt = require('jsonwebtoken');

function generateMcpToken(encryptionKey, userId) {
  let baseKey = '';
  for (let i = 0; i < encryptionKey.length; i += 2) {
    baseKey += encryptionKey[i];
  }
  const jwtSecret = crypto.createHash('sha256').update(baseKey).digest('hex');

  return jwt.sign({
    sub: userId,
    iss: 'n8n',
    aud: 'mcp-server-api',
    jti: crypto.randomUUID(),
  }, jwtSecret);
}
```

## Configuration

Key environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `N8N_ENCRYPTION_KEY` | 32-char key for encrypting credentials | Required |
| `N8N_BASIC_AUTH_USER` | Basic auth username | `admin` |
| `N8N_BASIC_AUTH_PASSWORD` | Basic auth password | `admin123` |
| `N8N_WEBHOOK_URL` | Public webhook URL | `http://localhost:5678/` |

## References

- [n8n Documentation](https://docs.n8n.io/)
- [n8n MCP Server](https://docs.n8n.io/advanced-ai/accessing-n8n-mcp-server/)
- [Model Context Protocol](https://modelcontextprotocol.io/)
