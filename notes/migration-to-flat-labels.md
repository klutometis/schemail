# Migration: Compound Labels → Flat Labels + Marker

## What Changed

**Before:**
- Labels: `Schemail/Receipt`, `Schemail/Newsletter`, `Schemail/Shipping`
- Structure: Hierarchical compound labels
- Query: Would need to enumerate all labels (impossible)

**After:**
- Content labels: `Receipt`, `Newsletter`, `Shipping` (flat, visible)
- Marker label: `Schemail` (hidden, for "processed" queries)
- Structure: Flat labels + hidden marker
- Query: `-label:Schemail` (simple, fast)

## If You Have Existing Emails with Old Labels

### Option 1: Leave Them (Recommended)

Old labels won't interfere with new system:
- Old emails keep `Schemail/Receipt` (visible)
- New emails get `Receipt` + `Schemail` (marker hidden)
- Query `-label:Schemail` will skip both old and new processed emails if you add `Schemail` marker to old ones

### Option 2: Migrate Existing Labels

If you want consistency, you can migrate:

```bash
# 1. Get all emails with old Schemail/* labels
# For each old label (e.g., Schemail/Receipt):

# 2. Find emails with that label
# 3. Add new labels: Receipt + Schemail
# 4. Remove old label: Schemail/Receipt

# This would require a migration script (not implemented yet)
```

### Option 3: Start Fresh

Delete all existing `Schemail/*` labels and reprocess emails:

```bash
# 1. In Gmail, delete all Schemail/* labels manually
# 2. Run classifier on all emails:
./bin/schemail process --last 1000 --classifier experiment-2 --execute
```

## Recommended Approach

**Just start using the new system:**
1. Old emails keep their `Schemail/*` labels (they work fine)
2. New emails get flat labels + `Schemail` marker
3. Over time, old labels will naturally be replaced as you reprocess/reclassify
4. No action required unless you want perfect consistency

## Manual Label Addition

If you manually add the `Schemail` marker to old emails with `Schemail/*` labels:

```bash
# Find all emails with Schemail/* labels
# Add Schemail marker to them
# Then query -label:Schemail will work consistently
```

But this is optional - the system works fine with mixed label structures.
