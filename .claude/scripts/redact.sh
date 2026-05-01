#!/usr/bin/env bash
# .claude/scripts/redact.sh
# Universal redaction library for secrets and sensitive environment variables
# Part of Secrets and Environment Protection Policy (docs/policy/secrets-and-env.md)

set -euo pipefail

# Configuration
REDACT_PARTIAL="${REDACT_PARTIAL:-false}"
REDACT_DISABLED="${REDACT_DISABLED:-false}"
REDACT_CLI_ARGS="${REDACT_CLI_ARGS:-true}"
REDACTION_TOKEN="***REDACTED***"

# Secret environment variable patterns (regex)
SECRET_PATTERNS=(
  # Token patterns
  "_TOKEN$"
  "_TOKEN="
  "^TOKEN="
  "AUTH_TOKEN"
  "API_TOKEN"
  "ACCESS_TOKEN"
  "REFRESH_TOKEN"
  "GITHUB_TOKEN"
  "GITLAB_TOKEN"

  # Secret patterns
  "_SECRET$"
  "_SECRET="
  "CLIENT_SECRET"
  "SESSION_SECRET"
  "JWT_SECRET"
  "WEBHOOK_SECRET"

  # Key patterns
  "_KEY$"
  "_KEY="
  "API_KEY"
  "PRIVATE_KEY"
  "ANTHROPIC_API_KEY"
  "SUPABASE_.*_KEY"
  "ENCRYPTION_KEY"

  # Password patterns
  "_PASSWORD$"
  "_PASSWORD="
  "_PASS$"
  "_PASS="
  "PGPASSWORD"
  "PGPASSFILE"
  "DB_PASSWORD"
  "POSTGRES_PASSWORD"
  "MYSQL_PASSWORD"
  "REDIS_PASSWORD"

  # Database URLs
  "DATABASE_URL"
  "DB_URL"
  "MONGODB_URI"
  "REDIS_URL"
  "POSTGRES_URL"
  "MYSQL_URL"
  "CONNECTION_STRING"

  # Cloud provider credentials
  "AWS_ACCESS_KEY_ID"
  "AWS_SECRET_ACCESS_KEY"
  "AWS_SESSION_TOKEN"
  "AWS_SECURITY_TOKEN"
  "GCP_SERVICE_ACCOUNT_KEY"
  "GOOGLE_APPLICATION_CREDENTIALS"
  "AZURE_CLIENT_SECRET"
  "AZURE_TENANT_ID"

  # Kubernetes/Docker
  "KUBECONFIG"
  "KUBE_TOKEN"
  "DOCKER_PASSWORD"
  "DOCKER_AUTH"
  "DOCKER_CONFIG"

  # Terraform
  "TF_VAR_.*"
  "TERRAFORM_.*_TOKEN"

  # NPM/Yarn
  "NPM_TOKEN"
  "YARN_.*_TOKEN"

  # Other credentials
  "SLACK_TOKEN"
  "SLACK_WEBHOOK"
  "SENTRY_AUTH_TOKEN"
  "TWILIO_AUTH_TOKEN"
  "STRIPE_SECRET_KEY"
  "PAYPAL_SECRET"
)

# CLI argument flag names (for --flag=value pattern matching)
CLI_SECRET_FLAG_NAMES="token|api-key|apikey|api_key|password|pass|secret|auth|authorization|bearer|key|private-key|client-secret|access-key|secret-key|session-token|webhook-secret|credentials"

# Connection string protocols (for protocol://user:pass@host/db pattern matching)
CONNECTION_PROTOS="postgres|postgresql|mysql|mongodb|redis|amqp|rabbitmq|kafka|cassandra|elasticsearch|clickhouse|neo4j|couchdb|influxdb|timescaledb|cockroachdb|mariadb|mssql|oracle|sqlite"

# Value-based token patterns (for recognizing tokens by their format)
VALUE_TOKEN_PATTERN='(sk-ant-api[0-9]+-[A-Za-z0-9_-]{95,}|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|AKIA[0-9A-Z]{16}|github_pat_[0-9a-zA-Z_]{70,}|ghp_[0-9a-zA-Z]{36}|gho_[0-9a-zA-Z]{36}|ya29\.[0-9A-Za-z_-]+|AIza[0-9A-Za-z_-]{30,})'

# Allowlist: environment variables that are NOT secrets
ALLOWLIST=(
  "NODE_ENV"
  "PATH"
  "HOME"
  "USER"
  "SHELL"
  "LANG"
  "LC_.*"
  "DISPLAY"
  "TERM"
  "PWD"
  "OLDPWD"
  "SHLVL"
  "EDITOR"
  "PAGER"
  "PORT"
  "LOG_LEVEL"
  "DEBUG"
)

# Secret file extensions and patterns
SECRET_FILE_PATTERNS=(
  "\.env$"
  "\.env\..*$"
  "\.pem$"
  "\.key$"
  "\.p12$"
  "\.pfx$"
  "credentials\.json$"
  "service-account\.json$"
  ".*-credentials\.json$"
  "secrets\.ya?ml$"
  "vault-pass$"
  "id_rsa$"
  "id_dsa$"
  "id_ed25519$"

  # Kubernetes config files
  "^config$"
  "\.kubeconfig$"
  "kube-config$"

  # Terraform state files
  "\.tfstate$"
  "\.tfstate\.backup$"
  "\.tfvars$"
  "terraform\.tfvars$"

  # Docker config
  "\.dockercfg$"
  "\.docker/config\.json$"

  # NPM/Yarn
  "\.npmrc$"
  "\.yarnrc$"

  # Database passwords
  "\.pgpass$"

  # Generic auth files
  "\.netrc$"
  "\.authinfo$"
)

# Check if redaction is disabled
if [[ "$REDACT_DISABLED" == "true" ]]; then
  redact_stream() { cat; }
  redact_file() { cat "$1"; }
  is_secret_file() { return 1; }
  return 0 2>/dev/null || exit 0
fi

# Function: is_secret_file
# Check if a file path matches secret file patterns
# Usage: if is_secret_file "/path/to/.env"; then ...; fi
# Returns: 0 (true) if secret file, 1 (false) otherwise
is_secret_file() {
  local file_path="$1"
  local basename
  basename="$(basename "$file_path")"

  for pattern in "${SECRET_FILE_PATTERNS[@]}"; do
    if echo "$basename" | grep -qE "$pattern"; then
      return 0
    fi
  done

  return 1
}

# Function: is_secret_var
# Check if an environment variable name matches secret patterns
# Usage: if is_secret_var "API_TOKEN"; then ...; fi
# Returns: 0 (true) if secret, 1 (false) otherwise
is_secret_var() {
  local var_name="$1"

  # Check allowlist first
  for allowed in "${ALLOWLIST[@]}"; do
    if echo "$var_name" | grep -qE "^${allowed}$"; then
      return 1
    fi
  done

  # Check secret patterns
  for pattern in "${SECRET_PATTERNS[@]}"; do
    if echo "$var_name" | grep -qE "$pattern"; then
      return 0
    fi
  done

  return 1
}

# Function: redact_value
# Redact a single value (with optional partial redaction)
# Usage: redacted=$(redact_value "secret123")
redact_value() {
  local value="$1"

  if [[ "$REDACT_PARTIAL" == "true" && ${#value} -gt 4 ]]; then
    echo "${value:0:4}***"
  else
    echo "$REDACTION_TOKEN"
  fi
}

# Function: _redact_cli_flags
# Redact command-line flags (--token=value or --token "value")
# Usage: echo "$line" | _redact_cli_flags
_redact_cli_flags() {
  local line="$1"

  # Case-insensitive pattern - specify both cases explicitly
  local flag_pattern="[Tt][Oo][Kk][Ee][Nn]|[Aa][Pp][Ii]-[Kk][Ee][Yy]|[Aa][Pp][Ii][Kk][Ee][Yy]|[Aa][Pp][Ii]_[Kk][Ee][Yy]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Pp][Aa][Ss][Ss]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Uu][Tt][Hh]|[Aa][Uu][Tt][Hh][Oo][Rr][Ii][Zz][Aa][Tt][Ii][Oo][Nn]|[Bb][Ee][Aa][Rr][Ee][Rr]|[Kk][Ee][Yy]|[Pp][Rr][Ii][Vv][Aa][Tt][Ee]-[Kk][Ee][Yy]|[Cc][Ll][Ii][Ee][Nn][Tt]-[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Cc][Cc][Ee][Ss][Ss]-[Kk][Ee][Yy]|[Ss][Ee][Cc][Rr][Ee][Tt]-[Kk][Ee][Yy]|[Ss][Ee][Ss][Ss][Ii][Oo][Nn]-[Tt][Oo][Kk][Ee][Nn]|[Ww][Ee][Bb][Hh][Oo][Oo][Kk]-[Ss][Ee][Cc][Rr][Ee][Tt]|[Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll][Ss]"

  # Pattern: --flag=value (no quotes)
  line=$(echo "$line" | sed -E "s/--(${flag_pattern})=([^[:space:]]*)/--\1=$REDACTION_TOKEN/g")

  # Pattern: --flag="value" (double quotes)
  line=$(echo "$line" | sed -E "s/--(${flag_pattern})=\"([^\"]*)\"/--\1=\"$REDACTION_TOKEN\"/g")

  # Pattern: --flag 'value' (single quotes)
  line=$(echo "$line" | sed -E "s/--(${flag_pattern}) '([^']*)'/--\1 '$REDACTION_TOKEN'/g")

  # Pattern: --flag "value" (space-separated with double quotes)
  line=$(echo "$line" | sed -E "s/--(${flag_pattern}) \"([^\"]*)\"/--\1 \"$REDACTION_TOKEN\"/g")

  # Pattern: --flag value (space-separated, no quotes)
  line=$(echo "$line" | sed -E "s/--(${flag_pattern}) ([^[:space:]]*)/--\1 $REDACTION_TOKEN/g")

  echo "$line"
}

# Function: _redact_connection_strings
# Redact connection strings (protocol://user:pass@host/db)
# Usage: echo "$line" | _redact_connection_strings
_redact_connection_strings() {
  local line="$1"

  # Pattern: protocol://[user[:pass]@]host[:port]/db
  # Redact entire connection string when credentials are present
  # Use multiple sed calls for BSD sed compatibility (macOS)
  line=$(echo "$line" | sed -E "s|(postgres://[^[:space:]@]*:[^[:space:]@]*@[^[:space:]]*)|postgres://$REDACTION_TOKEN|g")
  line=$(echo "$line" | sed -E "s|(postgresql://[^[:space:]@]*:[^[:space:]@]*@[^[:space:]]*)|postgresql://$REDACTION_TOKEN|g")
  line=$(echo "$line" | sed -E "s|(mysql://[^[:space:]@]*:[^[:space:]@]*@[^[:space:]]*)|mysql://$REDACTION_TOKEN|g")
  line=$(echo "$line" | sed -E "s|(mongodb://[^[:space:]@]*:[^[:space:]@]*@[^[:space:]]*)|mongodb://$REDACTION_TOKEN|g")
  line=$(echo "$line" | sed -E "s|(redis://[^[:space:]@]*:[^[:space:]@]*@[^[:space:]]*)|redis://$REDACTION_TOKEN|g")
  line=$(echo "$line" | sed -E "s|(amqp://[^[:space:]@]*:[^[:space:]@]*@[^[:space:]]*)|amqp://$REDACTION_TOKEN|g")
  line=$(echo "$line" | sed -E "s|(rabbitmq://[^[:space:]@]*:[^[:space:]@]*@[^[:space:]]*)|rabbitmq://$REDACTION_TOKEN|g")
  line=$(echo "$line" | sed -E "s|(kafka://[^[:space:]@]*:[^[:space:]@]*@[^[:space:]]*)|kafka://$REDACTION_TOKEN|g")
  line=$(echo "$line" | sed -E "s|(cassandra://[^[:space:]@]*:[^[:space:]@]*@[^[:space:]]*)|cassandra://$REDACTION_TOKEN|g")
  line=$(echo "$line" | sed -E "s|(elasticsearch://[^[:space:]@]*:[^[:space:]@]*@[^[:space:]]*)|elasticsearch://$REDACTION_TOKEN|g")

  echo "$line"
}

# Function: _redact_value_tokens
# Redact value-based tokens (Anthropic API keys, JWTs, AWS keys, GitHub PATs, etc.)
# Usage: echo "$line" | _redact_value_tokens
_redact_value_tokens() {
  local line="$1"

  # Replace matched token patterns with REDACTION_TOKEN
  line=$(echo "$line" | sed -E "s/$VALUE_TOKEN_PATTERN/$REDACTION_TOKEN/g")

  echo "$line"
}

# Function: redact_stream
# Redact secrets from stdin line by line
# Usage: cat file.txt | redact_stream
# Usage: echo "API_KEY=secret" | redact_stream
redact_stream() {
  local line var_name var_value redacted_value

  while IFS= read -r line; do
    # Pattern 1: export VAR=value or VAR=value (shell format)
    if echo "$line" | grep -qE '^[[:space:]]*(export[[:space:]]+)?[A-Z_][A-Z0-9_]*='; then
      var_name=$(echo "$line" | sed -E 's/^[[:space:]]*(export[[:space:]]+)?([A-Z_][A-Z0-9_]*)=.*/\2/')

      if is_secret_var "$var_name"; then
        # Extract everything before '=' and the actual value
        local prefix actual_value
        prefix=$(echo "$line" | sed -E 's/^([^=]*=).*/\1/')
        actual_value=$(echo "$line" | sed -E 's/^[^=]*=//')
        redacted_value=$(redact_value "$actual_value")
        echo "${prefix}${redacted_value}"
        continue
      fi
    fi

    # Pattern 2: JSON key-value pairs ("key": "value")
    if echo "$line" | grep -qE '"[a-z_]+"[[:space:]]*:[[:space:]]*"[^"]+"'; then
      local json_key
      json_key=$(echo "$line" | sed -E 's/.*"([a-z_]+)"[[:space:]]*:.*/\1/')

      if is_secret_var "$(echo "$json_key" | tr '[:lower:]' '[:upper:]')"; then
        echo "$line" | sed -E 's/(:[[:space:]]*")[^"]+(")/\1'"$REDACTION_TOKEN"'\2/'
        continue
      fi
    fi

    # CLI Argument patterns (3-7) — only if REDACT_CLI_ARGS is enabled
    if [[ "$REDACT_CLI_ARGS" == "true" ]]; then
      local modified_line="$line"

      # Pattern 3: Command-line flags (--token=value, --token "value")
      modified_line=$(_redact_cli_flags "$modified_line")

      # Pattern 4: HTTP Authorization headers
      # Authorization: Bearer xxx
      modified_line=$(echo "$modified_line" | sed -E "s/(Authorization:[[:space:]]*Bearer[[:space:]]+)[^[:space:]]*/\1$REDACTION_TOKEN/gi")
      # X-API-Key: xxx
      modified_line=$(echo "$modified_line" | sed -E "s/(X-API-Key:[[:space:]]*)[^[:space:]]*/\1$REDACTION_TOKEN/gi")

      # Pattern 5: Connection strings (protocol://user:pass@host/db)
      modified_line=$(_redact_connection_strings "$modified_line")

      # Pattern 6: Inline KEY=VALUE (mid-line, not at start)
      # Match common secret variable patterns in mid-line position
      # Use * instead of + to allow bare TOKEN, SECRET, etc.
      modified_line=$(echo "$modified_line" | sed -E "s/([[:space:]][A-Z_][A-Z0-9_]*TOKEN)=([^[:space:]]*)/\1=$REDACTION_TOKEN/g")
      modified_line=$(echo "$modified_line" | sed -E "s/([[:space:]][A-Z_][A-Z0-9_]*SECRET)=([^[:space:]]*)/\1=$REDACTION_TOKEN/g")
      modified_line=$(echo "$modified_line" | sed -E "s/([[:space:]][A-Z_][A-Z0-9_]*KEY)=([^[:space:]]*)/\1=$REDACTION_TOKEN/g")
      modified_line=$(echo "$modified_line" | sed -E "s/([[:space:]][A-Z_][A-Z0-9_]*PASSWORD)=([^[:space:]]*)/\1=$REDACTION_TOKEN/g")
      modified_line=$(echo "$modified_line" | sed -E "s/([[:space:]][A-Z_][A-Z0-9_]*PASS)=([^[:space:]]*)/\1=$REDACTION_TOKEN/g")
      # Also match bare TOKEN, PASSWORD, SECRET, KEY at mid-line
      modified_line=$(echo "$modified_line" | sed -E "s/([[:space:]]TOKEN)=([^[:space:]]*)/\1=$REDACTION_TOKEN/g")
      modified_line=$(echo "$modified_line" | sed -E "s/([[:space:]]PASSWORD)=([^[:space:]]*)/\1=$REDACTION_TOKEN/g")
      modified_line=$(echo "$modified_line" | sed -E "s/([[:space:]]SECRET)=([^[:space:]]*)/\1=$REDACTION_TOKEN/g")

      # Pattern 7: Value-based tokens (Anthropic API keys, JWTs, AWS keys, etc.)
      modified_line=$(_redact_value_tokens "$modified_line")

      # Output the modified line if any changes were made
      if [[ "$modified_line" != "$line" ]]; then
        echo "$modified_line"
        continue
      fi
    fi

    # No patterns matched, output original line
    echo "$line"
  done
}

# Function: redact_file
# Redact secrets from a file and output to stdout
# Usage: redact_file "/path/to/.env"
redact_file() {
  local file_path="$1"

  if [[ ! -f "$file_path" ]]; then
    echo "ERROR: File not found: $file_path" >&2
    return 1
  fi

  # If it's a secret file (binary or credential file), return placeholder
  if is_secret_file "$file_path"; then
    local basename
    basename="$(basename "$file_path")"

    # For binary secret files (.pem, .key, .p12, etc.), return placeholder
    if echo "$basename" | grep -qE '\.(pem|key|p12|pfx|crt|cer|der|jks)$'; then
      echo "[REDACTED SECRET FILE: $basename]"
      return 0
    fi

    # For JSON credential files, return placeholder
    if echo "$basename" | grep -qE 'credentials\.json|service-account\.json'; then
      echo "[REDACTED SECRET FILE: $basename]"
      return 0
    fi
  fi

  # Otherwise, redact line by line
  redact_stream < "$file_path"
}

# If script is executed directly (not sourced), process file or stdin
# Works in both bash and zsh
if [[ -n "${BASH_SOURCE:-}" && "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -gt 0 ]]; then
    # File argument provided
    redact_file "$1"
  else
    # No arguments, read from stdin
    redact_stream
  fi
elif [[ -n "${ZSH_VERSION:-}" && "${(%):-%x}" == "${0}" ]]; then
  if [[ $# -gt 0 ]]; then
    # File argument provided
    redact_file "$1"
  else
    # No arguments, read from stdin
    redact_stream
  fi
fi
