# MVP Operations Reference

Comprehensive list of operations available for each integrated service in the Autonomous Multi-Agent Software Factory.

**Legend:**
- 🟢 **READ**: Non-mutating, no approval needed
- 🟡 **WRITE**: Mutating, requires `--confirm` flag
- 🔴 **INFRASTRUCTURE**: Destructive, requires `--confirm --force`

---

## 1. Kubernetes (kubectl)

**Current Status:** READ tier via MCP (`ops_discover_k8s`), WRITE/INFRASTRUCTURE tier via shell wrappers (future)

### 🟢 READ Operations (Available via MCP)

| Operation | Command | Purpose | Example |
|-----------|---------|---------|---------|
| **List Namespaces** | `kubectl get namespaces` | View all namespaces | Discovery of cluster structure |
| **List Pods** | `kubectl get pods -n <ns>` | View all pods in namespace | Check deployment status |
| **List Services** | `kubectl get services -n <ns>` | View all services | Check service endpoints |
| **List Deployments** | `kubectl get deployments -n <ns>` | View all deployments | Check application versions |
| **Describe Resource** | `kubectl describe <type> <name> -n <ns>` | Detailed resource info | Debug pod issues |
| **Get Logs** | `kubectl logs <pod> -n <ns>` | View container logs | Application debugging |
| **Get Events** | `kubectl get events -n <ns>` | View cluster events | Troubleshoot failures |
| **Check Node Status** | `kubectl get nodes` | View node health | Cluster capacity planning |

### 🟡 WRITE Operations (Via approval workflow)

| Operation | Command | Purpose | Approval Required |
|-----------|---------|---------|-------------------|
| **Apply Manifest** | `kubectl apply -f <file>` | Create/update resources | Plan + Approve + Execute |
| **Patch Resource** | `kubectl patch <type> <name>` | Modify resource field | Plan + Approve + Execute |
| **Scale Deployment** | `kubectl scale deployment <name> --replicas=N` | Adjust replica count | Plan + Approve + Execute |
| **Restart Deployment** | `kubectl rollout restart deployment <name>` | Rolling restart | Plan + Approve + Execute |
| **Create ConfigMap** | `kubectl create configmap <name>` | Store configuration | Plan + Approve + Execute |
| **Create Secret** | `kubectl create secret <type> <name>` | Store sensitive data | Plan + Approve + Execute |

### 🔴 INFRASTRUCTURE Operations (Via approval workflow)

| Operation | Command | Purpose | Approval Required |
|-----------|---------|---------|-------------------|
| **Delete Pod** | `kubectl delete pod <name> -n <ns>` | Force pod termination | Plan + Approve + Execute + Force |
| **Delete Deployment** | `kubectl delete deployment <name>` | Remove application | Plan + Approve + Execute + Force |
| **Delete Service** | `kubectl delete service <name>` | Remove service endpoint | Plan + Approve + Execute + Force |
| **Delete Namespace** | `kubectl delete namespace <name>` | Remove entire namespace | Plan + Approve + Execute + Force |
| **Delete PVC** | `kubectl delete pvc <name>` | Remove persistent volume | Plan + Approve + Execute + Force |
| **Drain Node** | `kubectl drain <node>` | Evacuate node for maintenance | Plan + Approve + Execute + Force |

---

## 2. Argo CD (argocd)

**Current Status:** READ tier via MCP (`ops_discover_argocd`), WRITE/INFRASTRUCTURE tier via shell wrappers (future)

### 🟢 READ Operations (Available via MCP)

| Operation | Command | Purpose | Example |
|-----------|---------|---------|---------|
| **List Applications** | `argocd app list` | View all Argo CD apps | Deployment overview |
| **Get Application** | `argocd app get <app-name>` | Detailed app info | Check sync status |
| **Show App Diff** | `argocd app diff <app-name>` | Git vs cluster diff | Preview changes |
| **Get Sync History** | `argocd app history <app-name>` | View deployment history | Audit trail |
| **List Repos** | `argocd repo list` | Connected Git repositories | Verify repo access |
| **Get Project** | `argocd proj get <project>` | Project configuration | RBAC review |

### 🟡 WRITE Operations (Via approval workflow)

| Operation | Command | Purpose | Approval Required |
|-----------|---------|---------|-------------------|
| **Sync Application** | `argocd app sync <app-name>` | Deploy Git changes | Plan + Approve + Execute |
| **Hard Refresh** | `argocd app get <app-name> --hard-refresh` | Force refresh app state | Plan + Approve + Execute |
| **Rollback** | `argocd app rollback <app-name> <revision>` | Revert to previous version | Plan + Approve + Execute |
| **Set Param** | `argocd app set <app-name> --parameter key=value` | Update app parameter | Plan + Approve + Execute |
| **Create App** | `argocd app create <app-name>` | Register new application | Plan + Approve + Execute |
| **Enable Auto-Sync** | `argocd app set <app-name> --sync-policy automated` | Continuous deployment | Plan + Approve + Execute |

### 🔴 INFRASTRUCTURE Operations (Via approval workflow)

| Operation | Command | Purpose | Approval Required |
|-----------|---------|---------|-------------------|
| **Delete Application** | `argocd app delete <app-name>` | Unregister app (cascade delete) | Plan + Approve + Execute + Force |
| **Delete Application (Cascade)** | `argocd app delete <app-name> --cascade` | Delete app + K8s resources | Plan + Approve + Execute + Force |
| **Terminate Sync** | `argocd app terminate-op <app-name>` | Kill ongoing sync operation | Plan + Approve + Execute + Force |

---

## 3. Argo Workflows (argo)

**Current Status:** READ tier via MCP (`ops_discover_argo_workflows`), WRITE/INFRASTRUCTURE tier via shell wrappers (future)

### 🟢 READ Operations (Available via MCP)

| Operation | Command | Purpose | Example |
|-----------|---------|---------|---------|
| **List Workflows** | `argo list -n <ns>` | View all workflows | Check pipeline status |
| **List All Namespaces** | `argo list -A` | Workflows across all namespaces | Cluster-wide overview |
| **Get Workflow** | `argo get <workflow-name> -n <ns>` | Detailed workflow info | Debug failed step |
| **Get Logs** | `argo logs <workflow-name> -n <ns>` | View workflow logs | Troubleshoot errors |
| **Watch Workflow** | `argo watch <workflow-name> -n <ns>` | Real-time status updates | Monitor execution |
| **Get Node Status** | `argo node <workflow-name> <node-id>` | Individual step details | Debug specific task |

### 🟡 WRITE Operations (Via approval workflow)

| Operation | Command | Purpose | Approval Required |
|-----------|---------|---------|-------------------|
| **Submit Workflow** | `argo submit <workflow-file> -n <ns>` | Start new workflow execution | Plan + Approve + Execute |
| **Submit with Parameters** | `argo submit <file> -p key=value` | Parameterized workflow run | Plan + Approve + Execute |
| **Resubmit Workflow** | `argo resubmit <workflow-name> -n <ns>` | Re-run completed workflow | Plan + Approve + Execute |
| **Retry Failed Workflow** | `argo retry <workflow-name> -n <ns>` | Retry failed steps only | Plan + Approve + Execute |
| **Resume Suspended** | `argo resume <workflow-name> -n <ns>` | Continue suspended workflow | Plan + Approve + Execute |
| **Suspend Workflow** | `argo suspend <workflow-name> -n <ns>` | Pause running workflow | Plan + Approve + Execute |

### 🔴 INFRASTRUCTURE Operations (Via approval workflow)

| Operation | Command | Purpose | Approval Required |
|-----------|---------|---------|-------------------|
| **Stop Workflow** | `argo stop <workflow-name> -n <ns>` | Graceful shutdown (ongoing steps complete) | Plan + Approve + Execute + Force |
| **Terminate Workflow** | `argo terminate <workflow-name> -n <ns>` | Immediate kill (no cleanup) | Plan + Approve + Execute + Force |
| **Delete Workflow** | `argo delete <workflow-name> -n <ns>` | Remove workflow from history | Plan + Approve + Execute + Force |
| **Delete Completed** | `argo delete --completed -n <ns>` | Bulk cleanup completed workflows | Plan + Approve + Execute + Force |

**Example Use Cases:**
- **Resubmit**: Re-run entire data pipeline with same parameters
- **Retry**: Retry only failed steps (e.g., network timeout on one task)
- **Stop**: Allow ongoing ETL to finish current batch, then stop
- **Terminate**: Immediate kill (e.g., runaway resource consumption)
- **Delete**: Cleanup workflow history to free database space

---

## 4. PostgreSQL (psql)

**Current Status:** READ tier via MCP (`ops_discover_postgres`), WRITE/INFRASTRUCTURE tier via shell wrappers (future)

### 🟢 READ Operations (Available via MCP)

| Operation | SQL Command | Purpose | Example |
|-----------|-------------|---------|---------|
| **List Databases** | `\l` or `SELECT datname FROM pg_database` | View all databases | Database inventory |
| **List Schemas** | `\dn` or `SELECT schema_name FROM information_schema.schemata` | View schemas in database | Schema discovery |
| **List Tables** | `\dt` or `SELECT tablename FROM pg_tables WHERE schemaname='public'` | View tables | Data model exploration |
| **Describe Table** | `\d <table>` or `SELECT column_name, data_type FROM information_schema.columns WHERE table_name='<table>'` | Table structure | Schema review |
| **Count Rows** | `SELECT COUNT(*) FROM <table>` | Row count (with LIMIT) | Data volume check |
| **Select Query** | `SELECT * FROM <table> LIMIT 100` | Read data (max 1000 rows) | Data inspection |
| **Explain Query** | `EXPLAIN ANALYZE <query>` | Query execution plan | Performance analysis |
| **Check Indexes** | `\di` or `SELECT indexname FROM pg_indexes WHERE tablename='<table>'` | List indexes | Index optimization |

### 🟡 WRITE Operations (Via approval workflow)

| Operation | SQL Command | Purpose | Approval Required |
|-----------|-------------|---------|-------------------|
| **Insert Row** | `INSERT INTO <table> VALUES (...)` | Add new record | Plan + Approve + Execute |
| **Update Rows** | `UPDATE <table> SET col=val WHERE condition` | Modify existing data | Plan + Approve + Execute |
| **Delete Rows** | `DELETE FROM <table> WHERE condition` | Remove records | Plan + Approve + Execute |
| **Create Index** | `CREATE INDEX idx_name ON <table> (column)` | Add index for performance | Plan + Approve + Execute |
| **Run Migration** | `psql -f migration.sql` | Execute SQL migration file | Plan + Approve + Execute |
| **Vacuum Table** | `VACUUM <table>` | Reclaim storage space | Plan + Approve + Execute |

### 🔴 INFRASTRUCTURE Operations (Via approval workflow)

| Operation | SQL Command | Purpose | Approval Required |
|-----------|-------------|---------|-------------------|
| **Drop Table** | `DROP TABLE <table>` | Delete table permanently | Plan + Approve + Execute + Force |
| **Truncate Table** | `TRUNCATE TABLE <table>` | Delete all rows (fast) | Plan + Approve + Execute + Force |
| **Drop Database** | `DROP DATABASE <dbname>` | Delete entire database | Plan + Approve + Execute + Force |
| **Alter Table** | `ALTER TABLE <table> ...` | Modify table structure | Plan + Approve + Execute + Force |
| **Drop Index** | `DROP INDEX <index_name>` | Remove index | Plan + Approve + Execute + Force |
| **Reset Sequence** | `ALTER SEQUENCE <seq> RESTART WITH 1` | Reset auto-increment | Plan + Approve + Execute + Force |

**Safety Features:**
- All READ queries run in `READ ONLY` transaction mode
- Row limit enforced (default 100, max 1000) to prevent memory exhaustion
- Connection strings redacted in all output
- DDL operations automatically escalated to INFRASTRUCTURE tier

---

## 5. Supabase

**Current Status:** READ tier via MCP (`ops_discover_supabase`), WRITE/INFRASTRUCTURE tier via shell wrappers (future)

### 🟢 READ Operations (Available via MCP)

| Operation | Command | Purpose | Example |
|-----------|---------|---------|---------|
| **Project Status** | `supabase status` | View project configuration | Connectivity check |
| **List Functions** | `supabase functions list` | View Edge Functions | Function inventory |
| **Get Database Status** | `supabase db dump` (dry-run) | Check database health | Backup readiness |
| **Storage List** | `supabase storage ls <bucket>` | List storage objects | File management |
| **View Remote Changes** | `supabase db diff` | Show pending migrations | Pre-migration review |

### 🟡 WRITE Operations (Via approval workflow)

| Operation | Command | Purpose | Approval Required |
|-----------|---------|---------|-------------------|
| **Database Migration** | `supabase db push` | Apply pending migrations | Plan + Approve + Execute |
| **Deploy Function** | `supabase functions deploy <name>` | Deploy Edge Function | Plan + Approve + Execute |
| **Upload Storage** | `supabase storage cp <file> <bucket>/<path>` | Upload file to storage | Plan + Approve + Execute |
| **Update Secret** | `supabase secrets set KEY=value` | Store environment secret | Plan + Approve + Execute |
| **Generate Types** | `supabase gen types typescript --local` | Generate TypeScript types | Plan + Approve + Execute |

### 🔴 INFRASTRUCTURE Operations (Via approval workflow)

| Operation | Command | Purpose | Approval Required |
|-----------|---------|---------|-------------------|
| **Database Reset** | `supabase db reset` | Drop all data, re-run migrations | Plan + Approve + Execute + Force |
| **Unlink Project** | `supabase unlink` | Disconnect from remote project | Plan + Approve + Execute + Force |
| **Delete Function** | `supabase functions delete <name>` | Remove Edge Function | Plan + Approve + Execute + Force |
| **Delete Storage Object** | `supabase storage rm <bucket>/<path>` | Delete file from storage | Plan + Approve + Execute + Force |
| **Delete Bucket** | `supabase storage delete-bucket <name>` | Remove entire storage bucket | Plan + Approve + Execute + Force |

---

## 6. AWS S3 / Supabase Storage

**Current Status:** READ tier via MCP (`ops_discover_s3`), WRITE/INFRASTRUCTURE tier via shell wrappers (future)

### 🟢 READ Operations (Available via MCP)

| Operation | Command | Purpose | Example |
|-----------|---------|---------|---------|
| **List Buckets** | `aws s3 ls` | View all S3 buckets | Bucket inventory |
| **List Objects** | `aws s3 ls s3://<bucket>/` | View bucket contents | File discovery |
| **Get Bucket Info** | `aws s3api get-bucket-location --bucket <name>` | Bucket region/config | Compliance check |
| **Get Object Metadata** | `aws s3api head-object --bucket <b> --key <k>` | File metadata | Versioning info |
| **Check Bucket Size** | `aws s3 ls s3://<bucket> --summarize` | Total size and object count | Storage audit |

### 🟡 WRITE Operations (Via approval workflow)

| Operation | Command | Purpose | Approval Required |
|-----------|---------|---------|-------------------|
| **Upload File** | `aws s3 cp <local> s3://<bucket>/<key>` | Upload object to S3 | Plan + Approve + Execute |
| **Copy Object** | `aws s3 cp s3://<src> s3://<dst>` | Copy within/between buckets | Plan + Approve + Execute |
| **Set ACL** | `aws s3api put-object-acl --bucket <b> --key <k> --acl <acl>` | Update permissions | Plan + Approve + Execute |
| **Enable Versioning** | `aws s3api put-bucket-versioning --bucket <b> --versioning-configuration Status=Enabled` | Turn on versioning | Plan + Approve + Execute |
| **Create Bucket** | `aws s3 mb s3://<bucket-name>` | Create new bucket | Plan + Approve + Execute |

### 🔴 INFRASTRUCTURE Operations (Via approval workflow)

| Operation | Command | Purpose | Approval Required |
|-----------|---------|---------|-------------------|
| **Delete Object** | `aws s3 rm s3://<bucket>/<key>` | Remove single file | Plan + Approve + Execute + Force |
| **Delete Bucket** | `aws s3 rb s3://<bucket>` | Remove empty bucket | Plan + Approve + Execute + Force |
| **Delete Bucket (Force)** | `aws s3 rb s3://<bucket> --force` | Remove bucket + all contents | Plan + Approve + Execute + Force |
| **Delete All Versions** | `aws s3api delete-objects --bucket <b> --delete "$(aws s3api list-object-versions --bucket <b> --output=json --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"` | Remove all object versions | Plan + Approve + Execute + Force |

**Note:** For Supabase Storage, credentials are `SUPABASE_STORAGE_ACCESS_KEY_ID` and `SUPABASE_STORAGE_SECRET_KEY`, not standard AWS credentials.

---

## 7. GitHub (gh CLI)

**Current Status:** READ tier via MCP (`ops_discover_github`), WRITE/INFRASTRUCTURE tier via shell wrappers (future)

### 🟢 READ Operations (Available via MCP)

| Operation | Command | Purpose | Example |
|-----------|---------|---------|---------|
| **Repo Info** | `gh repo view` | View repository metadata | Repo statistics |
| **List Workflows** | `gh workflow list` | View GitHub Actions workflows | CI/CD inventory |
| **Workflow Runs** | `gh run list --workflow=<name>` | Recent workflow executions | Build history |
| **List Releases** | `gh release list` | View all releases | Version history |
| **List Branches** | `gh api repos/{owner}/{repo}/branches` | View all branches | Branch management |
| **View PR** | `gh pr view <number>` | Pull request details | Code review |
| **Check Status** | `gh run view <run-id>` | Workflow run status | CI/CD monitoring |

### 🟡 WRITE Operations (Via approval workflow)

| Operation | Command | Purpose | Approval Required |
|-----------|---------|---------|-------------------|
| **Create PR** | `gh pr create --title "..." --body "..."` | Open pull request | Plan + Approve + Execute |
| **Merge PR** | `gh pr merge <number>` | Merge pull request | Plan + Approve + Execute |
| **Trigger Workflow** | `gh workflow run <workflow-name>` | Manually trigger CI/CD | Plan + Approve + Execute |
| **Create Release** | `gh release create <tag> --notes "..."` | Publish new release | Plan + Approve + Execute |
| **Add Label** | `gh pr edit <number> --add-label <label>` | Tag pull request | Plan + Approve + Execute |
| **Close Issue** | `gh issue close <number>` | Close GitHub issue | Plan + Approve + Execute |

### 🔴 INFRASTRUCTURE Operations (Via approval workflow)

| Operation | Command | Purpose | Approval Required |
|-----------|---------|---------|-------------------|
| **Delete Branch** | `gh api --method DELETE repos/{owner}/{repo}/git/refs/heads/<branch>` | Remove branch permanently | Plan + Approve + Execute + Force |
| **Delete Release** | `gh release delete <tag> --yes` | Remove release + tag | Plan + Approve + Execute + Force |
| **Force Push** | `git push --force` (via gh wrapper) | Rewrite branch history | Plan + Approve + Execute + Force |
| **Delete Repo** | `gh repo delete <owner>/<repo> --yes` | Remove entire repository | Plan + Approve + Execute + Force |
| **Cancel Workflow** | `gh run cancel <run-id>` | Kill running workflow | Plan + Approve + Execute + Force |

---

## 8. Docker

**Current Status:** READ tier via MCP (`ops_discover_docker`), WRITE/INFRASTRUCTURE tier via shell wrappers (future)

### 🟢 READ Operations (Available via MCP)

| Operation | Command | Purpose | Example |
|-----------|---------|---------|---------|
| **List Containers** | `docker ps` | View running containers | Runtime inventory |
| **List All Containers** | `docker ps -a` | Running + stopped containers | Full container list |
| **List Images** | `docker images` | View local images | Image inventory |
| **Inspect Container** | `docker inspect <container>` | Detailed container config | Debug networking |
| **Container Logs** | `docker logs <container>` | View container output | Application debugging |
| **List Networks** | `docker network ls` | View Docker networks | Network topology |
| **List Volumes** | `docker volume ls` | View persistent volumes | Storage management |
| **Check Stats** | `docker stats --no-stream` | Resource usage snapshot | Performance monitoring |

### 🟡 WRITE Operations (Via approval workflow)

| Operation | Command | Purpose | Approval Required |
|-----------|---------|---------|-------------------|
| **Start Container** | `docker start <container>` | Start stopped container | Plan + Approve + Execute |
| **Stop Container** | `docker stop <container>` | Graceful shutdown | Plan + Approve + Execute |
| **Restart Container** | `docker restart <container>` | Stop + start | Plan + Approve + Execute |
| **Build Image** | `docker build -t <name> <path>` | Create image from Dockerfile | Plan + Approve + Execute |
| **Tag Image** | `docker tag <image> <new-tag>` | Add image tag | Plan + Approve + Execute |
| **Push Image** | `docker push <image>` | Upload to registry | Plan + Approve + Execute |
| **Create Network** | `docker network create <name>` | Create custom network | Plan + Approve + Execute |
| **Create Volume** | `docker volume create <name>` | Create persistent volume | Plan + Approve + Execute |

### 🔴 INFRASTRUCTURE Operations (Via approval workflow)

| Operation | Command | Purpose | Approval Required |
|-----------|---------|---------|-------------------|
| **Kill Container** | `docker kill <container>` | Force terminate (no cleanup) | Plan + Approve + Execute + Force |
| **Remove Container** | `docker rm <container>` | Delete stopped container | Plan + Approve + Execute + Force |
| **Remove Image** | `docker rmi <image>` | Delete local image | Plan + Approve + Execute + Force |
| **Remove Volume** | `docker volume rm <volume>` | Delete persistent volume | Plan + Approve + Execute + Force |
| **Remove Network** | `docker network rm <network>` | Delete custom network | Plan + Approve + Execute + Force |
| **Prune System** | `docker system prune -a` | Remove unused containers/images/volumes | Plan + Approve + Execute + Force |
| **Force Remove Image** | `docker rmi -f <image>` | Delete image (ignore dependencies) | Plan + Approve + Execute + Force |

---

## 9. Redis

**Current Status:** READ tier via MCP (`ops_discover_redis`), WRITE/INFRASTRUCTURE tier via shell wrappers (future)

### 🟢 READ Operations (Available via MCP)

| Operation | Command | Purpose | Example |
|-----------|---------|---------|---------|
| **Server Info** | `redis-cli INFO server` | View Redis version/uptime | Health check |
| **Memory Stats** | `redis-cli INFO memory` | Memory usage details | Capacity planning |
| **Keyspace Stats** | `redis-cli INFO keyspace` | Database key counts | Data inventory |
| **Client List** | `redis-cli CLIENT LIST` | Connected clients | Connection monitoring |
| **Get Key** | `redis-cli GET <key>` | Read key value | Data inspection |
| **Key Type** | `redis-cli TYPE <key>` | Check key data type | Schema validation |
| **Key TTL** | `redis-cli TTL <key>` | Time to expiration | Cache debugging |
| **List Keys** | `redis-cli KEYS <pattern>` | Find keys by pattern (use SCAN in prod) | Key discovery |

### 🟡 WRITE Operations (Via approval workflow)

| Operation | Command | Purpose | Approval Required |
|-----------|---------|---------|-------------------|
| **Set Key** | `redis-cli SET <key> <value>` | Store key-value pair | Plan + Approve + Execute |
| **Set with TTL** | `redis-cli SETEX <key> <seconds> <value>` | Store with expiration | Plan + Approve + Execute |
| **Delete Key** | `redis-cli DEL <key>` | Remove single key | Plan + Approve + Execute |
| **Increment** | `redis-cli INCR <key>` | Atomic increment | Plan + Approve + Execute |
| **Hash Set** | `redis-cli HSET <hash> <field> <value>` | Store hash field | Plan + Approve + Execute |
| **List Push** | `redis-cli LPUSH <list> <value>` | Add to list | Plan + Approve + Execute |
| **Expire Key** | `redis-cli EXPIRE <key> <seconds>` | Set TTL on existing key | Plan + Approve + Execute |

### 🔴 INFRASTRUCTURE Operations (Via approval workflow)

| Operation | Command | Purpose | Approval Required |
|-----------|---------|---------|-------------------|
| **Flush Database** | `redis-cli FLUSHDB` | Delete all keys in current DB | Plan + Approve + Execute + Force |
| **Flush All Databases** | `redis-cli FLUSHALL` | Delete all keys in all DBs | Plan + Approve + Execute + Force |
| **Save Snapshot** | `redis-cli BGSAVE` | Create background RDB snapshot | Plan + Approve + Execute + Force |
| **Shutdown Server** | `redis-cli SHUTDOWN` | Stop Redis server | Plan + Approve + Execute + Force |
| **Rewrite AOF** | `redis-cli BGREWRITEAOF` | Compact append-only file | Plan + Approve + Execute + Force |

---

## Approval Workflow Summary

All **🟡 WRITE** and **🔴 INFRASTRUCTURE** operations follow this 4-step workflow:

### Step 1: Plan Mutation
```javascript
ops_plan_mutation({
  tier: "WRITE",  // or "INFRASTRUCTURE"
  operation: "kubectl_scale",
  scope: { namespace: "production", resource: "deployment/api" },
  params: { replicas: 5 },
  dry_run_output: "... kubectl output with --dry-run ..."
})
// Returns: { plan_id, plan_hash, status: "pending_approval" }
```

### Step 2: Review Plan (Optional)
```javascript
ops_list_pending({})
// Returns: List of pending plans with details

ops_plan_history({ plan_id, show_diff: true })
// Returns: Version history and diffs
```

### Step 3: Approve Plan
```javascript
ops_approve({
  plan_id: "plan_1739212800_abc123",
  plan_hash: "f3e8d9c7b6a5..."  // Must match to prevent tampering
})
// Returns: { approved: true, expires_at: "2026-02-10T20:00:00Z" }
```

### Step 4: Execute Plan
```javascript
ops_execute({
  plan_id: "plan_1739212800_abc123"
})
// Returns: { success: true, output: "... (redacted) ..." }
```

### Audit Trail
```javascript
ops_audit_log({ plan_id: "plan_1739212800_abc123" })
// Returns: Complete audit log (who/what/when) for compliance
```

---

## Quick Reference: Operations by Use Case

### Deploy New Application Version
1. **Check current state**: `ops_discover_k8s` → list deployments
2. **Review pending changes**: `argocd app diff <app-name>` (READ)
3. **Sync application**: `ops_plan_mutation` → `ops_approve` → `ops_execute` (WRITE)
4. **Verify deployment**: `kubectl get pods -n <ns>` (READ)
5. **Check logs**: `kubectl logs <pod>` (READ)

### Scale Application
1. **Check current replicas**: `ops_discover_k8s` (READ)
2. **Plan scale operation**: `ops_plan_mutation` (tier: WRITE, operation: kubectl_scale)
3. **Approve**: `ops_approve`
4. **Execute**: `ops_execute`
5. **Verify**: `kubectl get deployment <name>` (READ)

### Run Data Pipeline
1. **Check existing workflows**: `ops_discover_argo_workflows` (READ)
2. **Submit workflow**: `ops_plan_mutation` (tier: WRITE, operation: argo_submit)
3. **Approve + Execute**: Standard workflow
4. **Monitor progress**: `argo logs <workflow-name>` (READ)
5. **Check results**: PostgreSQL SELECT query (READ)

### Database Migration
1. **Review migration SQL**: Read file locally
2. **Dry-run migration**: PostgreSQL EXPLAIN (READ)
3. **Plan migration**: `ops_plan_mutation` (tier: INFRASTRUCTURE, operation: postgres_migrate)
4. **Approve + Execute**: Standard workflow
5. **Verify schema**: `\d <table>` (READ)

### Cleanup Failed Workflows
1. **List failed workflows**: `argo list --status Failed` (READ)
2. **Plan deletion**: `ops_plan_mutation` (tier: INFRASTRUCTURE, operation: argo_delete, params: [list of workflow names])
3. **Approve + Execute**: Standard workflow
4. **Verify cleanup**: `argo list` (READ)

### Emergency Stop Runaway Container
1. **Identify container**: `docker ps` (READ)
2. **Check resource usage**: `docker stats` (READ)
3. **Plan termination**: `ops_plan_mutation` (tier: INFRASTRUCTURE, operation: docker_kill)
4. **Approve + Execute**: Standard workflow (expedited)
5. **Verify stopped**: `docker ps` (READ)

---

## Security Notes

1. **All operations are audited**: Every command execution logged with timestamp, actor, parameters
2. **Output redaction**: Secrets, tokens, IPs automatically redacted before logging
3. **Dry-run default**: WRITE operations default to dry-run unless `--confirm` provided
4. **Hash verification**: Plan tampering detected via SHA256 hash mismatch
5. **TTL enforcement**: Approved plans expire after 30 minutes (configurable)
6. **Scope validation**: Operations require explicit namespace/database/bucket specification
7. **No cluster-wide defaults**: Prevents accidental broad-spectrum changes

---

## Tool Availability Matrix

| Service | READ via MCP | WRITE/INFRA via Approval | Shell Wrappers | Status |
|---------|--------------|--------------------------|----------------|--------|
| Kubernetes | ✅ `ops_discover_k8s` | ✅ Via `ops_plan_mutation` + execute | 🔮 Future (k8s.sh) | Phase 5.1 + 5.3 |
| Argo CD | ✅ `ops_discover_argocd` | ✅ Via approval workflow | 🔮 Future (argocd.sh) | Phase 5.1 + 5.3 |
| Argo Workflows | ✅ `ops_discover_argo_workflows` | ✅ Via approval workflow | 🔮 Future (argo-workflows.sh) | Phase 5.2 + 5.3 |
| PostgreSQL | ✅ `ops_discover_postgres` | ✅ Via approval workflow | 🔮 Future (postgres.sh) | Phase 5.1 + 5.3 |
| Supabase | ✅ `ops_discover_supabase` | ✅ Via approval workflow | 🔮 Future (supabase.sh) | Phase 5.1 + 5.3 |
| AWS S3 | ✅ `ops_discover_s3` | ✅ Via approval workflow | 🔮 Future (s3.sh) | Phase 5.2 + 5.3 |
| GitHub | ✅ `ops_discover_github` | ✅ Via approval workflow | 🔮 Future (github.sh) | Phase 5.2 + 5.3 |
| Docker | ✅ `ops_discover_docker` | ✅ Via approval workflow | 🔮 Future (docker.sh) | Phase 5.2 + 5.3 |
| Redis | ✅ `ops_discover_redis` | ✅ Via approval workflow | 🔮 Future (redis.sh) | Phase 5.2 + 5.3 |

**Legend:**
- ✅ **Implemented**: Currently available
- 🔮 **Future**: Planned for Stage 4 (shell wrapper layer)
- Phase 5.1: Initial 4 discovery tools
- Phase 5.2: Extended 5 discovery tools
- Phase 5.3: Approval workflow + unified discovery

---

## Further Reading

- **Full policy documentation**: [docs/policy/ops-tools.md](policy/ops-tools.md)
- **MCP security model**: [docs/policy/mcp-security.md](policy/mcp-security.md)
- **Approval workflow spec**: [docs/policy/ops-tools.md#approval-workflow-usage-examples](policy/ops-tools.md#approval-workflow-usage-examples)
- **Troubleshooting guide**: [docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md)
