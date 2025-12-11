# ELK Stack Log Retention - Kibana UI Only Guide
## Hot-Warm-Delete Strategy (90-Day Retention) - Web Navigation Only

**Document Version**: 1.0  
**Target Environment**: Ubuntu Single-Node ELK Stack (Free/Basic License)  
**Approach**: 100% Kibana Web UI - No API/Dev Tools Required  
**Retention Policy**: 90 Days  

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Phase 1: Create Master ILM Policy (Kibana UI)](#phase-1-create-master-ilm-policy-kibana-ui)
4. [Phase 2: Future-Proof Configuration (Scenario A)](#phase-2-future-proof-configuration-scenario-a)
5. [Phase 3: Fixing Existing Logs (Scenario B)](#phase-3-fixing-existing-logs-scenario-b)
6. [Monitoring ILM Status (Kibana UI)](#monitoring-ilm-status-kibana-ui)
7. [Troubleshooting](#troubleshooting)

---

## Overview

This guide walks you through the **entire process using ONLY Kibana's web interface**. No command-line tools, no API calls, no Dev Tools console required. Everything is point-and-click through the Kibana UI.

### Architecture Recap

- **Hot Phase**: New logs actively indexed (auto-rollover at 25GB or 30 days)
- **Warm Phase**: Transition immediately with Force Merge to 1 segment (space optimization)
- **Delete Phase**: Auto-delete after 90 days

---

## Prerequisites

### Access Kibana

1. Open your web browser
2. Navigate to: `http://your-elk-server:5601`
3. Log in with your Kibana credentials
4. You should see the Kibana home page with the main menu on the left

**Expected Screen**: Kibana dashboard with sidebar menu visible

---

## Phase 1: Create Master ILM Policy (Kibana UI)

### Step 1: Navigate to Index Lifecycle Policies

1. In the **left sidebar**, click **Stack Management** (gear icon at the bottom)
   - If not visible, look for the menu icon (☰) in the top-left and expand it

   ![Location of Stack Management]
   - Under **Data**, you'll see several options

2. Click **Index Lifecycle Policies** (under the **Data** section)

   **Expected Screen**: A page showing existing ILM policies (if any)

### Step 2: Create a New Policy

1. Click the **Create Policy** button (usually blue, top-right area)

   **Expected Screen**: A form titled "Create lifecycle policy"

2. In the **Policy Name** field, enter:
   ```
   prod-90-days-universal
   ```

3. Do NOT click "Use recommended defaults" — leave it OFF (unchecked)

### Step 3: Configure the Hot Phase

The **Hot Phase** should already be enabled (shown in a card/section).

1. Scroll down to the **Hot phase** section
2. Look for the **Rollover** toggle — make sure it's **ON** (enabled)
3. Set the rollover conditions:
   - **Max primary shard size**: `25` GB
   - **Max age**: `30` days

4. Look for **Set priority** option
   - Toggle to **ON** (enabled)
   - Set **Priority**: `100`

### Step 4: Configure the Warm Phase

1. Find the **Warm phase** section (if not visible, scroll down)
2. Click the **toggle switch** to enable the **Warm phase** (turn it ON)

   **Expected Screen**: The warm phase section expands

3. Set **Min age**: Leave as `0d` (this means transition immediately after hot phase ends)

4. Now add individual warm phase actions by expanding **Advanced settings**:
   
   #### Add Set Priority Action:
   - Look for a button/option to **Add action** or click where it shows warm phase actions
   - Select **Set Priority** from the list
   - Set Priority value: `50`
   - Click **Add** or **Confirm**

   #### Add Force Merge Action:
   - Click **Add action** again (if needed)
   - Select **Force merge** from the list
   - Set **Max segments**: `1` (CRITICAL — this is the space-saving step)
   - Click **Add** or **Confirm**

   #### Add Allocate Action:
   - Click **Add action** again
   - Select **Allocate** from the list
   - Set **Number of replicas**: `0` (single-node cluster)
   - Click **Add** or **Confirm**

### Step 5: Configure the Delete Phase

1. Find the **Delete phase** section (scroll down)
2. Click the **toggle switch** to enable the **Delete phase** (turn it ON)

   **Expected Screen**: The delete phase section expands

3. Set **Min age**: `90` days (this is your retention period)
4. The **Delete** action should be automatically enabled
5. You should see "Delete" listed as an action

### Step 6: Save the Policy

1. Review all settings:
   - Hot: Rollover at 25GB/30d + Priority 100
   - Warm: Min age 0d + Set Priority 50 + Force Merge (1 segment) + Allocate (0 replicas)
   - Delete: Min age 90d

2. Click the **Save Policy** button (usually blue, bottom-right)

   **Expected Screen**: You should see a success message, and the policy `prod-90-days-universal` now appears in the policy list

### Step 7: Verify Policy Creation

1. You should be back on the **Index Lifecycle Policies** page
2. Search for `prod-90-days-universal` in the policy list
3. Click on the policy name to view its details and confirm all phases are configured correctly

   **Expected Output**:
   - Policy name: `prod-90-days-universal`
   - Hot: Rollover at 25GB, 30d
   - Warm: Force merge to 1 segment, replicas 0
   - Delete: 90d

---

## Phase 2: Future-Proof Configuration (Scenario A)

### Important Note

Component templates and custom index templates in Kibana UI have **limited visibility**. The recommended approach for Kibana UI is to ensure that **when you create new data streams**, they automatically pick up the `prod-90-days-universal` policy.

### Step 1: Check Existing Index Templates

1. In **Stack Management**, look for **Index Management** (under **Data** section)
2. Click on **Index Management**
3. At the top, you should see tabs: **Indices**, **Data Streams**, **Index Templates**, **Component Templates**
4. Click **Index Templates**

   **Expected Screen**: A list of existing templates

5. Look for templates related to your integrations:
   - `logs-panw*` (Palo Alto)
   - `logs-sophos*` (Sophos)
   - `logs-*security*` or `logs-endpoint*` (Endpoint Security)

### Step 2: Edit Existing Templates (Limited UI Support)

Unfortunately, **Kibana UI does NOT provide a full template editor for component templates**. 

**If you have custom integration templates**, the UI approach is limited. However, you can:

1. In **Index Templates** tab, find templates like `logs-panw*`, `logs-sophos*`
2. Click on the template name
3. Look for an **Edit** button (if available)
4. Some Kibana versions allow you to see the template composition, but editing is restricted

**Workaround for Scenario A**:
- For **new logs ingested going forward**, they will use the ILM policy assigned through the integration's default setup
- You will manually update existing indices in **Phase 3** (Scenario B)

---

## Phase 3: Fixing Existing Logs (Scenario B)

This is where the Kibana UI really shines. You'll bulk-change the ILM policy for all existing Palo Alto, Sophos, and Endpoint logs.

### Step 1: Open Index Management

1. In **Stack Management**, click **Index Management** (under **Data** section)
2. You should see three tabs: **Indices**, **Data Streams**, **Index Templates**, **Component Templates**

### Step 2: Check Your Current Indices and Data Streams

#### View All Data Streams:
1. Click the **Data Streams** tab
2. You'll see a list of all active data streams (e.g., `logs-panw.panos-default`, `logs-sophos.xg-default`)
3. Note which ones are active and which ILM policies they're using

   **Expected Screen**: List showing:
   - Name: `logs-panw.panos-default`
   - Backing indices: 1 or more
   - Status: Active

#### View All Indices:
1. Click the **Indices** tab
2. You'll see all individual indices
3. Use the **search/filter** box to find:
   - `logs-panw*` (Palo Alto logs)
   - `logs-sophos*` (Sophos logs)
   - `logs-endpoint*` or `logs-*security*` (Endpoint security logs)

### Step 3: Bulk Change Lifecycle Policy for Data Streams

**NOTE**: If your logs are in **Data Streams** (modern Elastic Agent setup):

1. Go to **Data Streams** tab
2. **Search and select** all data streams you want to update:
   - Type `logs-panw` in the search box
   - Check the **checkbox** next to the data stream name(s)
   - Repeat for `logs-sophos`, `logs-endpoint`, etc.

   **TIP**: Check the "Select all" checkbox at the top to select all visible results

3. Once you've selected all data streams, look for the **Actions** dropdown menu (top-right area)

4. Click **Actions** → **Change data stream settings**

   **Expected Screen**: A popup or modal asking you to confirm

5. You should see an option to change settings. Look for **index.lifecycle.name** or similar
   - If the UI provides a field, change it to: `prod-90-days-universal`
   
6. Click **Apply** or **Confirm**

   **Expected**: Success message saying settings were updated

### Step 4: Bulk Change Lifecycle Policy for Indices (If Not Using Data Streams)

**NOTE**: If your logs are stored as individual **Indices** (legacy setup):

1. Go to **Indices** tab

2. **Search and select** all indices you want to update:
   - Type `logs-panw` in the search box
   - Check the **checkbox** next to each index
   - Repeat for `logs-sophos`, `logs-endpoint`, etc.

   **TIP**: You can select multiple by holding Ctrl/Cmd and clicking, or use the "Select all" checkbox

3. Once selected, look for the **Actions** dropdown menu (top-right area)

4. Click **Actions** → **Change lifecycle policy**

   **Expected Screen**: A dropdown or modal appears asking you to select a policy

5. Select `prod-90-days-universal` from the dropdown

6. Click **Change policy** or **Confirm**

   **Expected**: Success message showing the policy was updated for all selected indices

### Step 5: Verify the Policy Change

1. Go back to the **Indices** or **Data Streams** tab
2. Search for `logs-panw*` (or your other integrations)
3. Click on one of the indices/data streams
4. In the details panel, look for the **Lifecycle policy** field
5. It should now show: `prod-90-days-universal`

   **Expected Output**:
   ```
   Index: logs-panw.panos-000001
   Lifecycle policy: prod-90-days-universal
   Phase: hot (or warm, depending on age)
   ```

---

## Monitoring ILM Status (Kibana UI)

### Method 1: Check ILM Explain via Index Management

1. Go to **Stack Management** → **Index Management** → **Indices** tab
2. Search for `logs-panw*` or `logs-sophos*`
3. Click on an index name to open its details panel
4. Scroll down to find the **Lifecycle** section
5. You should see:
   - **Policy**: `prod-90-days-universal`
   - **Phase**: hot / warm / delete
   - **Step**: rollover / forcemerge / delete
   - **Age**: How long the index has been in its current phase

### Method 2: Monitor via Data Streams Tab

1. Go to **Stack Management** → **Index Management** → **Data Streams** tab
2. Click on a data stream name (e.g., `logs-panw.panos-default`)
3. In the details panel, expand the **Lifecycle** section
4. You'll see the current phase and step for this data stream

### Method 3: Check Cluster Health (Dashboard View)

1. Go to **Stack Management** → **Cluster** (if available in your Kibana version)
2. Or click on **Monitoring** in the left sidebar (if enabled)
3. You should see a dashboard showing:
   - Cluster status (green = healthy)
   - Disk usage
   - Active shards

### Monitor ILM Execution Over Time

1. Open **Discover** or **Logs** in the left sidebar (depending on Kibana version)
2. Look for system or internal logs that mention "ilm" or "lifecycle"
3. You can set up alerts if available

---

## Troubleshooting

### Issue 1: Can't Find Index Lifecycle Policies in Stack Management

**Solution**:
1. Make sure you're in **Stack Management** (gear icon at bottom of left sidebar)
2. Look under **Data** section on the left
3. If you still don't see it:
   - Check your Kibana version (ILM management requires Kibana 7.4+)
   - Make sure you have admin or editor role

### Issue 2: Policy Changes Don't Appear on Indices

**Solution**:
1. Refresh the page (Ctrl+R or Cmd+R)
2. Go back to **Index Management** → **Indices** tab
3. Search for the specific index
4. Click on it and scroll to the **Lifecycle** section
5. Wait 1-2 minutes for the change to propagate

### Issue 3: "Lifecycle policy not found" Error

**Solution**:
1. Make sure you created the `prod-90-days-universal` policy BEFORE trying to apply it
2. Go to **Index Lifecycle Policies** and verify the policy exists
3. If it doesn't exist, go back to **Phase 1** and create it again

### Issue 4: Indices Stuck in "Waiting for Forcemerge"

**Solution**:
1. This is normal for large indices — force merge takes time
2. Go to **Stack Management** → **Index Management** → **Indices**
3. Search for the stuck index
4. Click on it and check the **Lifecycle** section
5. It should eventually move to "warm" phase
6. Wait 10-30 minutes depending on index size (25GB can take time)

### Issue 5: Cannot Change Policy — "Not Editable" Error

**Solution**:
1. Some managed indices (from Elastic Agent integrations) may have restrictions
2. Try selecting a different batch of indices that don't have restrictions
3. Or contact support if the integration is preventing policy changes

### Issue 6: Disk Space Still High After Deletion

**Solution**:
1. The delete phase may not have completed yet
2. Go to **Index Management** → **Indices**
3. Look for old indices (more than 90 days old)
4. If they still exist, they haven't been deleted by ILM yet
5. Wait another 1-2 hours for ILM to process
6. Or manually delete them (use **Actions** → **Delete index**) — use with caution!

### Issue 7: "Only 1 node available" or Replica Warnings

**Solution**:
1. This is expected on a single-node cluster
2. Make sure your warm phase has **Allocate** set to **0 replicas**
3. Go to **Phase 1, Step 4** and verify the setting
4. If needed, you can manually update indices by:
   - Going to **Index Management** → **Indices**
   - Selecting indices
   - **Actions** → **Edit settings** (if available)
   - Set replicas to 0

---

## Key Checkpoints — Verification Steps

After completing all three phases, verify the following using ONLY the Kibana UI:

### ✅ Checkpoint 1: Policy Created
1. **Stack Management** → **Index Lifecycle Policies**
2. Search for `prod-90-days-universal`
3. Click on it and verify:
   - Hot: Rollover 25GB, 30d ✓
   - Warm: Force merge 1 segment, replicas 0 ✓
   - Delete: 90d ✓

### ✅ Checkpoint 2: Policy Applied to Logs
1. **Stack Management** → **Index Management** → **Data Streams** tab
2. Search for `logs-panw` and click on it
3. Check **Lifecycle policy**: Should show `prod-90-days-universal` ✓
4. Repeat for `logs-sophos`, `logs-endpoint`, etc.

### ✅ Checkpoint 3: Indices in Correct Phase
1. **Stack Management** → **Index Management** → **Indices** tab
2. Search for `logs-panw*`
3. Click on an index
4. Check **Phase**: Should show "hot" or "warm" (depending on age) ✓
5. If index is >30 days old, it should be in "warm" with completed forcemerge ✓

### ✅ Checkpoint 4: Disk Space Being Reclaimed
1. **Stack Management** → **Cluster** or **Monitoring** tab (if available)
2. Check **Disk usage** — should be stable or decreasing over 90 days
3. Or go to **Index Management** → **Indices** and note the **Store size** column
4. Compare index sizes from a few days ago — should see compression from forcemerge ✓

### ✅ Checkpoint 5: Indices Deleted After 90 Days
1. **Stack Management** → **Index Management** → **Indices** tab
2. Search for indices older than 90 days
3. They should NOT appear in the list (indicating they've been deleted) ✓
4. If old indices still exist, wait for ILM to delete them

---

## Maintenance & Ongoing Monitoring

### Weekly Check

1. Open **Kibana** → **Stack Management** → **Index Management** → **Indices**
2. Look at the **Store size** column
3. If it's growing beyond your 450 GB limit:
   - Reduce retention from 90 days to 60 days
   - Or increase disk space
4. No action needed if stable

### Monthly Check

1. **Stack Management** → **Index Lifecycle Policies**
2. Click on `prod-90-days-universal`
3. Verify all phases are still correctly configured
4. Make adjustments if needed

### Alert Setup (If Available)

In newer Kibana versions:
1. Go to **Stack Management** → **Alerts and Actions**
2. Create an alert for:
   - Disk usage > 400 GB
   - ILM policy errors
   - Indices not transitioning to warm/delete phase

---

## Quick Reference: Common Kibana UI Paths

| Task | Path | Steps |
|------|------|-------|
| **Create ILM Policy** | Stack Management → Index Lifecycle Policies → Create Policy | 1. Name, 2. Configure phases, 3. Save |
| **View ILM Policies** | Stack Management → Index Lifecycle Policies | Click policy name to view details |
| **Check Index Status** | Stack Management → Index Management → Indices tab | Search pattern, click index, scroll to Lifecycle section |
| **Check Data Stream Status** | Stack Management → Index Management → Data Streams tab | Click data stream name, expand Lifecycle section |
| **Change Policy on Indices** | Stack Management → Index Management → Indices tab → Select multiple → Actions → Change lifecycle policy | 1. Select indices, 2. Choose policy, 3. Confirm |
| **Change Policy on Data Streams** | Stack Management → Index Management → Data Streams tab → Select multiple → Actions → Change data stream settings | 1. Select streams, 2. Update lifecycle, 3. Confirm |
| **Delete Old Indices** | Stack Management → Index Management → Indices tab → Select index → Actions → Delete index | Confirm deletion (use with caution!) |
| **Monitor Cluster Health** | Stack Management → Cluster (or Monitoring tab) | View disk usage, shard allocation, node status |

---

## Final Checklist — Kibana UI Only

Complete this checklist using **ONLY the Kibana web interface**:

- [ ] Can access Kibana at `http://your-elk-server:5601`
- [ ] Navigated to **Stack Management** successfully
- [ ] Created ILM policy `prod-90-days-universal` with all 3 phases
- [ ] Verified policy shows Hot (25GB, 30d) + Warm (merge 1, replicas 0) + Delete (90d)
- [ ] Located all Palo Alto, Sophos, and Endpoint data streams/indices
- [ ] Selected and applied `prod-90-days-universal` policy to Palo Alto logs
- [ ] Selected and applied `prod-90-days-universal` policy to Sophos logs
- [ ] Selected and applied `prod-90-days-universal` policy to Endpoint logs
- [ ] Verified in Index Management that indices now show `prod-90-days-universal` as their policy
- [ ] Observed indices transitioning from hot → warm phase
- [ ] Confirmed disk usage is stable within 450 GB limit
- [ ] Set reminder to check disk usage weekly
- [ ] Bookmarked this guide for reference

---

## Troubleshooting Contact

If you encounter issues not covered here:
1. Take a screenshot of the error
2. Note the exact Kibana UI path where you saw the error
3. Check Elasticsearch logs: **Stack Management** → **Logs** (if available)

---

**End of Document**

*This guide is 100% Kibana web interface based. No terminal, no API calls, no Dev Tools required. Everything is point-and-click navigation.*

Last Updated: December 11, 2025
