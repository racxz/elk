# ELK Stack Log Retention Configuration Guide
## Hot-Warm-Delete Strategy for Single-Node Deployment (90-Day Retention)

**Document Version**: 1.0  
**Target Environment**: Ubuntu Single-Node ELK Stack (Free/Basic License)  
**Storage Capacity**: 500 GB total (~450 GB usable)  
**Retention Policy**: 90 Days  
**Strategy**: Hot → Warm (with Force Merge) → Delete  

---

## Table of Contents

1. [Overview & Architecture](#overview--architecture)
2. [Prerequisites & Validation](#prerequisites--validation)
3. [Phase 1: Create Master ILM Policy](#phase-1-create-master-ilm-policy)
4. [Phase 2: Future-Proof Configuration (Scenario A)](#phase-2-future-proof-configuration-scenario-a)
5. [Phase 3: Fixing Existing Logs (Scenario B)](#phase-3-fixing-existing-logs-scenario-b)
6. [Monitoring & Troubleshooting](#monitoring--troubleshooting)
7. [Storage Calculation & Validation](#storage-calculation--validation)

---

## Overview & Architecture

### Why Hot-Warm-Delete for Single Node?

In a single-node Elasticsearch cluster, you **cannot use Cold or Frozen tiers** because they require node attributes and specialized hardware allocation that don't apply to a single node. Instead, this guide implements:

- **Hot Phase**: Actively receives and indexes new logs (default rollover)
- **Warm Phase**: Transitions to read-only immediately (0 days) with **Force Merge to 1 segment** to maximize space efficiency
- **Delete Phase**: Automatically removes indices after 90 days

### Force Merge Benefits

Force merging to a single segment (`max_num_segments: 1`) is critical for single-node deployments because it:

1. **Reclaims disk space** by consolidating all segments and permanently removing deleted documents
2. **Improves search performance** on warm (read-only) data by reducing segment overhead
3. **Reduces memory footprint** since Elasticsearch maintains fewer file handles
4. **Optimizes for storage constraints** when disk capacity is limited

---

## Prerequisites & Validation

### Step 1: Verify Cluster Health

Before making any changes, ensure your Elasticsearch cluster is healthy:

```bash
# SSH into your ELK server
ssh user@elk-server

# Check cluster health
curl -X GET "localhost:9200/_cluster/health?pretty"
```

**Expected Output:**
```json
{
  "cluster_name": "elasticsearch",
  "status": "green",
  "timed_out": false,
  "number_of_nodes": 1,
  "number_of_data_nodes": 1,
  "active_primary_shards": XX,
  "active_shards": XX,
  "relocating_shards": 0,
  "initializing_shards": 0,
  "unassigned_shards": 0,
  "delayed_unassigned_shards": 0,
  "number_of_pending_tasks": 0,
  "number_of_in_flight_fetch": 0,
  "task_max_waiting_in_queue_millis": 0,
  "active_shards_percent_as_number": 100.0
}
```

**Status must be "green"**. If it's yellow or red, investigate and resolve issues before proceeding.

### Step 2: Check Current Disk Usage

```bash
# Check disk usage
df -h

# Check Elasticsearch disk usage specifically
curl -X GET "localhost:9200/_cat/indices?v&h=index,store.size,docs.count" | head -20
```

Note your current storage consumption for baseline comparison.

### Step 3: Identify Existing Log Sources

List all active indices and data streams:

```bash
# List all indices
curl -X GET "localhost:9200/_cat/indices?v"

# List all data streams
curl -X GET "localhost:9200/_data_stream?pretty"
```

This helps you identify which logs are already present and which integrations (Palo Alto, Sophos, Endpoint Security) you need to manage.

---

## Phase 1: Create Master ILM Policy

The master ILM policy `prod-90-days-universal` is the foundation for all log retention. This policy will be applied to new indices through component templates and to existing indices through bulk updates.

### Step 1: Create the ILM Policy via API

Use the Kibana Dev Tools or curl to create the policy:

```bash
curl -X PUT "localhost:9200/_ilm/policy/prod-90-days-universal" \
  -H "Content-Type: application/json" \
  -d '{
    "policy": {
      "phases": {
        "hot": {
          "min_age": "0ms",
          "actions": {
            "rollover": {
              "max_primary_shard_size": "25gb",
              "max_age": "30d"
            },
            "set_priority": {
              "priority": 100
            }
          }
        },
        "warm": {
          "min_age": "0ms",
          "actions": {
            "set_priority": {
              "priority": 50
            },
            "forcemerge": {
              "max_num_segments": 1
            },
            "allocate": {
              "number_of_replicas": 0
            }
          }
        },
        "delete": {
          "min_age": "90d",
          "actions": {
            "delete": {}
          }
        }
      }
    }
  }'
```

**Policy Breakdown:**

| Phase | Trigger | Actions | Purpose |
|-------|---------|---------|---------|
| **Hot** | Index creation | Rollover at 25GB or 30 days; Priority 100 | Actively receives logs |
| **Warm** | Immediately (0ms) | Force Merge to 1 segment; Reduce replicas to 0; Priority 50 | Read-only state, optimize for storage |
| **Delete** | After 90 days | Delete index | Enforce 90-day retention |

### Step 2: Verify Policy Creation

```bash
# List all ILM policies
curl -X GET "localhost:9200/_ilm/policy?pretty"

# Get specific policy details
curl -X GET "localhost:9200/_ilm/policy/prod-90-days-universal?pretty"
```

**Expected Output:** The policy JSON you created should be returned.

### Step 3: Create the ILM Policy via Kibana UI (Alternative)

If you prefer the GUI:

1. Open **Kibana** → Navigate to **Stack Management** (left sidebar)
2. Click **Index Lifecycle Policies** under **Data** section
3. Click **Create Policy**
4. **Policy Name**: `prod-90-days-universal`
5. **Hot Phase** (automatically enabled):
   - Toggle **Use recommended defaults** → OFF
   - **Rollover**: Enable
     - Max primary shard size: `25gb`
     - Max age: `30d`
   - **Set Priority**: Enable
     - Priority: `100`
6. **Warm Phase**:
   - Click toggle to enable
   - **Min age**: Leave as `0d` (transitions immediately after rollover)
   - Click **Advanced settings** and add:
     - **Set Priority**: Priority `50`
     - **Force merge**: Max segments `1` (CRITICAL)
     - **Allocate**: Number of replicas `0` (single node, no replicas needed)
7. **Delete Phase**:
   - Click toggle to enable
   - **Min age**: `90d`
   - Delete action is auto-enabled
8. Click **Save Policy**

---

## Phase 2: Future-Proof Configuration (Scenario A)

### Creating the `logs@custom` Component Template

Component templates allow you to automatically apply the master ILM policy to all **new** data streams and indices. This is the "future-proof" approach.

### Step 1: Create ILM Settings Component Template

This component applies the ILM policy to new logs:

```bash
curl -X PUT "localhost:9200/_component_template/logs@custom" \
  -H "Content-Type: application/json" \
  -d '{
    "template": {
      "settings": {
        "index": {
          "lifecycle": {
            "name": "prod-90-days-universal",
            "rollover_alias": "logs"
          },
          "number_of_shards": 1,
          "number_of_replicas": 0,
          "codec": "best_compression"
        }
      }
    },
    "_meta": {
      "description": "Single-node ELK production logs - 90 day retention",
      "managed": true,
      "version": 1
    }
  }'
```

### Step 2: Verify Component Template

```bash
# List all component templates
curl -X GET "localhost:9200/_component_template?pretty"

# Get specific component template
curl -X GET "localhost:9200/_component_template/logs@custom?pretty"
```

### Step 3: Update Existing Index Templates to Use logs@custom

If you have existing index templates (especially from Elastic Agent/Fleet integrations), you need to ensure they use this component template.

#### For Palo Alto Logs:

```bash
# First, get the current Palo Alto template
curl -X GET "localhost:9200/_index_template/logs-panw*?pretty"

# Create or update a custom Palo Alto template with higher priority
curl -X PUT "localhost:9200/_index_template/logs-panw-custom" \
  -H "Content-Type: application/json" \
  -d '{
    "index_patterns": ["logs-panw.*"],
    "priority": 210,
    "data_stream": {},
    "composed_of": [
      "logs@custom",
      "logs@mappings",
      "ecs@mappings"
    ],
    "_meta": {
      "description": "Custom template for Palo Alto logs with universal 90-day retention"
    }
  }'
```

#### For Sophos Logs:

```bash
curl -X PUT "localhost:9200/_index_template/logs-sophos-custom" \
  -H "Content-Type: application/json" \
  -d '{
    "index_patterns": ["logs-sophos.*"],
    "priority": 210,
    "data_stream": {},
    "composed_of": [
      "logs@custom",
      "logs@mappings",
      "ecs@mappings"
    ],
    "_meta": {
      "description": "Custom template for Sophos logs with universal 90-day retention"
    }
  }'
```

#### For Endpoint Security Logs:

```bash
curl -X PUT "localhost:9200/_index_template/logs-endpoint-custom" \
  -H "Content-Type: application/json" \
  -d '{
    "index_patterns": ["logs-*security*", "logs-endpoint*"],
    "priority": 210,
    "data_stream": {},
    "composed_of": [
      "logs@custom",
      "logs@mappings",
      "ecs@mappings"
    ],
    "_meta": {
      "description": "Custom template for Endpoint/Security logs with universal 90-day retention"
    }
  }'
```

### Step 4: Trigger Rollover for New Indices

For **new logs to use the updated template**, you may need to trigger a rollover on existing data streams:

```bash
# For Palo Alto
curl -X POST "localhost:9200/logs-panw*/_rollover?pretty"

# For Sophos
curl -X POST "localhost:9200/logs-sophos*/_rollover?pretty"

# For general logs (if applicable)
curl -X POST "localhost:9200/logs*/_rollover?pretty"
```

**Note:** Rollover creates a new write index using the latest template configuration. Existing data remains on the old index until the ILM policy transitions it.

### Step 5: Verify Template Priority

List all index templates and verify `logs-panw-custom`, `logs-sophos-custom`, and `logs-endpoint-custom` have **priority 210** (higher than built-in templates at priority 200):

```bash
curl -X GET "localhost:9200/_index_template?pretty" | grep -A 5 "priority"
```

---

## Phase 3: Fixing Existing Logs (Scenario B)

Existing logs may be using the default Elastic Stack policies (e.g., `logs@lifecycle` for Palo Alto, Sophos). This scenario walks you through identifying and bulk-updating these indices to use `prod-90-days-universal`.

### Step 1: Identify "Stubborn" Integrations

Check which ILM policies are currently applied to your data streams and indices:

```bash
# Check data streams and their ILM policies
curl -X GET "localhost:9200/_data_stream?pretty" | grep -A 20 "name"

# Get detailed ILM policy assignment
curl -X GET "localhost:9200/logs-*/_ilm/explain?pretty" | grep -A 5 "index\|policy"
```

Look for patterns like:
- `logs-panw.panos-default` → uses `logs@lifecycle`
- `logs-sophos.xg-default` → uses `logs@lifecycle`
- `logs-system.*` → uses default policies

### Step 2: Check Current ILM Status

View the ILM explain output to see where indices are in their lifecycle:

```bash
curl -X GET "localhost:9200/_ilm/explain?pretty" > ilm_status.json
cat ilm_status.json | grep -E "index|phase|policy"
```

This shows:
- Current phase (hot, warm, delete)
- Time in current phase
- Actions executed/pending

### Step 3: Bulk Update Data Stream Settings

For **data streams** (the recommended approach for modern Elastic Agent integrations):

#### Update Palo Alto Data Stream:

```bash
curl -X PUT "localhost:9200/_data_stream/logs-panw.panos-default/_settings" \
  -H "Content-Type: application/json" \
  -d '{
    "index.lifecycle.name": "prod-90-days-universal"
  }'
```

#### Update Sophos Data Stream:

```bash
curl -X PUT "localhost:9200/_data_stream/logs-sophos.xg-default/_settings" \
  -H "Content-Type: application/json" \
  -d '{
    "index.lifecycle.name": "prod-90-days-universal"
  }'
```

#### Update All Matching Data Streams (Bulk):

```bash
# For all logs-* data streams
for ds in $(curl -s "localhost:9200/_data_stream?pretty" | grep '"name"' | awk -F'"' '{print $4}'); do
  echo "Updating data stream: $ds"
  curl -X PUT "localhost:9200/_data_stream/$ds/_settings" \
    -H "Content-Type: application/json" \
    -d '{
      "index.lifecycle.name": "prod-90-days-universal"
    }'
done
```

**Verify the update:**

```bash
curl -X GET "localhost:9200/_data_stream/logs-panw.panos-default?pretty" | grep "lifecycle"
```

### Step 4: Update Existing Backing Indices

For indices that are **NOT part of a data stream** (legacy setup):

```bash
# Update a single index
curl -X PUT "localhost:9200/logs-panw.panos-2024.12.11-000001/_settings" \
  -H "Content-Type: application/json" \
  -d '{
    "index.lifecycle.name": "prod-90-days-universal"
  }'
```

#### Bulk Update All Matching Indices:

Using Kibana Dev Tools or a bash script:

```bash
# Method 1: Update all indices matching a pattern
curl -X PUT "localhost:9200/logs-panw.*/_settings" \
  -H "Content-Type: application/json" \
  -d '{
    "index": {
      "lifecycle.name": "prod-90-days-universal"
    }
  }'

# Method 2: Update all logs-* indices (use with caution)
curl -X PUT "localhost:9200/logs-*/_settings" \
  -H "Content-Type: application/json" \
  -d '{
    "index": {
      "lifecycle.name": "prod-90-days-universal"
    }
  }'
```

### Step 5: Update via Kibana UI (Alternative Method)

1. Open **Kibana** → **Stack Management** → **Index Management**
2. In the **Indices** tab, search for the index pattern (e.g., `logs-panw*`, `logs-sophos*`)
3. Select all matching indices
4. Click **Actions** → **Change lifecycle policy**
5. Select `prod-90-days-universal` from the dropdown
6. Click **Change policy** (this applies to all selected indices)

**Note:** Existing indices will use the new policy starting from the next phase transition. The policy version is automatically incremented.

### Step 6: Verify ILM Policy Update

```bash
# Check that all indices now use the new policy
curl -X GET "localhost:9200/_ilm/explain?pretty" | grep -B 2 -A 2 "prod-90-days-universal"

# Or filter by index pattern
curl -X GET "localhost:9200/logs-panw*/_ilm/explain?pretty"
```

**Expected Output:**
```json
{
  "indices": {
    "logs-panw.panos-000001": {
      "index": "logs-panw.panos-000001",
      "managed": true,
      "policy": "prod-90-days-universal",
      "lifecycle_date_millis": 1702312260000,
      "age": "30d 15h 47m",
      "phase": "warm",
      "phase_time_millis": 1702398660000,
      "action": "forcemerge",
      "action_time_millis": 1702398660000,
      "step": "waiting_for_forcemerge",
      "step_time_millis": 1702398660000,
      "is_hot_shard": false,
      "is_searchable_snapshot": false
    }
  }
}
```

---

## Monitoring & Troubleshooting

### Monitor ILM Execution

```bash
# Real-time ILM status
curl -X GET "localhost:9200/_ilm/explain?pretty"

# Monitor specific phase
curl -X GET "localhost:9200/logs-*/_ilm/explain?pretty" | grep -E "phase|step|age"
```

### Common Issues and Solutions

#### Issue 1: Indices Stuck in "Waiting for Forcemerge"

**Cause**: The forcemerge action may be slow on large indices.

**Solution**:
```bash
# Manually trigger forcemerge
curl -X POST "localhost:9200/logs-panw.panos-000001/_forcemerge?max_num_segments=1&pretty"

# Monitor forcemerge progress
curl -X GET "localhost:9200/_tasks?detailed=true&actions=*forcemerge*&pretty"
```

#### Issue 2: ILM Policy Not Applied to New Data

**Cause**: Index template priority is too low or component template not composed correctly.

**Solution**:
```bash
# Check template composition
curl -X GET "localhost:9200/_index_template/logs-panw*?pretty"

# Verify logs@custom is included in "composed_of"
# If not, recreate the template with the correct composition
```

#### Issue 3: Disk Space Not Freed After Deletion

**Cause**: Indices deleted but segments not yet merged.

**Solution**:
```bash
# Force merge warm indices to reclaim space
curl -X POST "localhost:9200/logs-*/_forcemerge?max_num_segments=1&pretty"

# Wait for old indices to be deleted (per the ILM policy)
# Check deletion progress
curl -X GET "localhost:9200/_tasks?detailed=true&pretty"
```

#### Issue 4: "Cannot assign replicas to a single node"

**Cause**: ILM policy trying to set replicas on a single-node cluster.

**Solution**: Ensure all index templates and component templates have `"number_of_replicas": 0`.

```bash
# Verify current settings
curl -X GET "localhost:9200/logs-*/_settings?pretty" | grep "number_of_replicas"

# Force set to 0
curl -X PUT "localhost:9200/logs-*/_settings" \
  -H "Content-Type: application/json" \
  -d '{
    "index": {
      "number_of_replicas": 0
    }
  }'
```

### Enable ILM Verbosity Logging

To troubleshoot ILM issues, enable debug logging:

```bash
# Update Elasticsearch logging configuration
curl -X PUT "localhost:9200/_cluster/settings" \
  -H "Content-Type: application/json" \
  -d '{
    "transient": {
      "logger.org.elasticsearch.xpack.core.ilm": "DEBUG"
    }
  }'

# View logs
tail -f /path/to/elasticsearch/logs/elasticsearch.log | grep ilm
```

---

## Storage Calculation & Validation

### Formula for 90-Day Retention

```
Daily Log Volume (GB) = Total current index size (GB) / Days of current data

Total Storage Needed (90 days) = Daily Log Volume × 90

Example:
- Current 30-day data: 100 GB
- Daily volume: 100 GB ÷ 30 = 3.33 GB/day
- 90-day requirement: 3.33 × 90 = 300 GB
```

### Validate Against Your 450 GB Usable Space

```bash
# Check current disk usage
df -h /path/to/elasticsearch/data

# Check index sizes
curl -X GET "localhost:9200/_cat/indices?v&h=index,store.size,docs.count&s=store.size:desc"

# Get total storage usage
curl -X GET "localhost:9200/_cat/nodes?v&h=name,disk.used,disk.total,disk.percent"
```

### Projections & Adjustments

If your calculated 90-day requirement exceeds 450 GB:

**Option 1**: Reduce retention period
```bash
# Change delete phase from 90d to 60d
curl -X PUT "localhost:9200/_ilm/policy/prod-90-days-universal" \
  -H "Content-Type: application/json" \
  -d '{
    "policy": {
      "phases": {
        "delete": {
          "min_age": "60d",
          "actions": {
            "delete": {}
          }
        }
      }
    }
  }'
```

**Option 2**: Increase force merge aggressiveness
- Already set to `max_num_segments: 1` (optimal)
- Ensure best_compression codec is enabled in templates

**Option 3**: Increase disk storage
- Add a second disk and expand Elasticsearch data path
- Move to a larger instance type

---

## Appendix: JSON Reference for Copy-Paste

### Complete ILM Policy (JSON)

```json
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_primary_shard_size": "25gb",
            "max_age": "30d"
          },
          "set_priority": {
            "priority": 100
          }
        }
      },
      "warm": {
        "min_age": "0ms",
        "actions": {
          "set_priority": {
            "priority": 50
          },
          "forcemerge": {
            "max_num_segments": 1
          },
          "allocate": {
            "number_of_replicas": 0
          }
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

### Component Template: logs@custom (JSON)

```json
{
  "template": {
    "settings": {
      "index": {
        "lifecycle": {
          "name": "prod-90-days-universal",
          "rollover_alias": "logs"
        },
        "number_of_shards": 1,
        "number_of_replicas": 0,
        "codec": "best_compression"
      }
    }
  },
  "_meta": {
    "description": "Single-node ELK production logs - 90 day retention",
    "managed": true,
    "version": 1
  }
}
```

### Verification Commands Cheat Sheet

```bash
# 1. Cluster health
curl -X GET "localhost:9200/_cluster/health?pretty"

# 2. List ILM policies
curl -X GET "localhost:9200/_ilm/policy?pretty"

# 3. Get specific policy
curl -X GET "localhost:9200/_ilm/policy/prod-90-days-universal?pretty"

# 4. Check data streams
curl -X GET "localhost:9200/_data_stream?pretty"

# 5. ILM explain for all indices
curl -X GET "localhost:9200/_ilm/explain?pretty"

# 6. ILM explain for specific pattern
curl -X GET "localhost:9200/logs-panw*/_ilm/explain?pretty"

# 7. List indices and sizes
curl -X GET "localhost:9200/_cat/indices?v&h=index,store.size,docs.count&s=store.size:desc"

# 8. Disk usage
curl -X GET "localhost:9200/_cat/nodes?v&h=name,disk.used,disk.total,disk.percent"

# 9. Component templates
curl -X GET "localhost:9200/_component_template?pretty"

# 10. Index templates
curl -X GET "localhost:9200/_index_template?pretty"
```

---

## Final Checklist

Before going live with this configuration:

- [ ] Cluster health is **green**
- [ ] `prod-90-days-universal` ILM policy created
- [ ] `logs@custom` component template created
- [ ] Custom index templates created for Palo Alto, Sophos, Endpoint Security (priority 210+)
- [ ] All existing data streams updated to use `prod-90-days-universal`
- [ ] All existing indices updated to use `prod-90-days-universal`
- [ ] Rollovers triggered on active data streams
- [ ] ILM explain shows indices in correct phases
- [ ] Storage calculation validated against available space
- [ ] Monitoring/alerting configured for disk usage
- [ ] Documentation backed up for runbooks
- [ ] Test deletion on a non-critical 1-day retention policy first

---

## Support & References

- **Elastic ILM Documentation**: https://www.elastic.co/docs/manage-data/lifecycle/index-lifecycle-management
- **Index Templates**: https://www.elastic.co/docs/manage-data/data-store/data-streams
- **Force Merge API**: https://www.elastic.co/docs/reference/elasticsearch/indices/forcemerge
- **Data Streams**: https://www.elastic.co/docs/manage-data/data-store/data-streams/overview

---

**End of Document**

*This guide is tailored for single-node ELK deployments with storage constraints. Adapt the storage limits and retention periods according to your specific hardware and retention requirements.*
