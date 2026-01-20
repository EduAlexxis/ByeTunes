# The iOS Music Database: Complete Documentation

Based on extensive reverse-engineering and successful music injection experiments.

## 1. The "Golden Rule" for Stability

Every song MUST follow this pattern:

| Field | Value | Why? |
| :--- | :--- | :--- |
| **Integrity** | `generateIntegrityHex` (Fake Path) | Satisfies NOT NULL constraint. Cloud status bypasses strict checks. |
| **Location Kind** | `42` (Cloud/Unknown) | Relaxes local file verification. |
| **Base Location** | `3840` (`/iTunes_Control/Music`) | Physical path for MP3s. |
| **Artwork Token** | `"100" + TrackNum` (e.g., "1001") | Simple numeric string tokens are stable. |
| **Item Store** | `INSERT` (Enabled) | MUST insert `sync_id` + `sync_in_my_library = 1`. |

---

## 2. Artwork System (SOLVED ✅)

### The Complete Artwork Algorithm

**Key Discovery:** iOS computes artwork file paths from `SHA1(artwork_token)`, NOT from the image data!

```
artwork_token = "1001"
SHA1("1001") = dd01903921ea24941c26a48f2cec24e0bb0e8cc7
file_path = /iTunes_Control/iTunes/Artwork/Originals/dd/01903921ea24941c26a48f2cec24e0bb0e8cc7
relative_path (in DB) = "dd/01903921ea24941c26a48f2cec24e0bb0e8cc7"
```

### Required Database Tables for Artwork

#### A. `artwork` Table
| Column | Value | Notes |
|--------|-------|-------|
| `artwork_token` | `"1001"` | Numeric string token |
| `artwork_source_type` | `300` | Local source |
| `relative_path` | `"dd/01903921..."` | SHA1(token) split as XX/rest |
| `artwork_type` | `1` | Standard artwork |
| `interest_data` | ColorAnalysis JSON | **REQUIRED for album view** |
| `artwork_variant_type` | `0` | Default |

**ColorAnalysis JSON Example:**
```json
{"ColorAnalysis":{"1":{"primaryTextColorLight":"NO","secondaryTextColorLight":"NO","secondaryTextColor":"#FFFFFF","tertiaryTextColorLight":"NO","primaryTextColor":"#FFFFFF","tertiaryTextColor":"#CCCCCC","backgroundColorLight":"NO","backgroundColor":"#333333"}}}
```

#### B. `artwork_token` Table
Links entities to artwork tokens.

| entity_type | Description | Required |
|-------------|-------------|----------|
| `0` | Song (item_pid) | ✅ Yes |
| `1` | Album table reference | ✅ Yes |
| `2` | Artist | Optional |
| `4` | **Album artwork in library view** | ✅ CRITICAL |
| `7` | Remote artist image | N/A |

**INSERT Example:**
```sql
INSERT INTO artwork_token (artwork_token, artwork_source_type, artwork_type, entity_pid, entity_type, artwork_variant_type)
VALUES ('1001', 300, 1, <entity_pid>, <entity_type>, 0);
```

#### C. `best_artwork_token` Table
**CRITICAL:** `fetchable_artwork_token` MUST be empty for local artwork!

| Column | Value for Local Art | Notes |
|--------|---------------------|-------|
| `available_artwork_token` | `"1001"` | The token we provide |
| `fetchable_artwork_token` | `""` (empty) | **MUST be empty!** |
| `fetchable_artwork_source_type` | `0` | Not remote |

If `fetchable_artwork_token` is set, iOS tries to fetch remotely, fails, and shows fallback color.

### Artwork File Requirements
- **Format:** JPEG (JFIF standard 1.01)
- **Resolution:** Recommended 640x640
- **Location:** `/iTunes_Control/iTunes/Artwork/Originals/XX/hashvalue`
- **Naming:** No extension, just the hash value as filename

---

## 3. Previously Solved Issues

### The "Queue Crash"
**Cause:** Inconsistent Sort Map entries or Artwork Token conflicts.
**Fix:** Populate `sort_map` for every string and use simple numeric artwork tokens.

### The "Ghost Album"
**Cause:** Missing `item_store` entry.
**Fix:** Always insert into `item_store` with `sync_in_my_library = 1`.

### The "Not Available" Error
**Cause:** Conflict between Location Kind and Integrity.
**Fix:** Set `Location Kind = 42` to bypass integrity verification.

---

## 4. Technical Schema Reference

### `item` (Master Table)
- `item_pid`: Unique 64-bit ID
- `base_location_id`: `3840`
- `media_type`: `8` (Song), `16384` (Ringtone)

### `item_extra` (Metadata)
- `location`: Filename only (e.g., `ABCD.mp3`)
- `integrity`: Checksum field
- `location_kind_id`: `42`

### `item_store` (Visibility)
- `sync_id`: Random non-zero integer
- `sync_in_my_library`: `1`

### `sort_map` (Navigation)
- Every string needs a row here
- `name_order`: Integer ID for sorting

### `album` Table
- `representative_item_pid`: First song's item_pid (for artwork inheritance)

---

## 5. File System Layout

```
/iTunes_Control/
├── Music/
│   └── F00/           <- MP3 files (renamed to 4char.mp3)
├── iTunes/
│   ├── MediaLibrary.sqlitedb
│   └── Artwork/
│       ├── Originals/
│       │   ├── dd/    <- Folder = first 2 chars of SHA1(token)
│       │   │   └── 01903921ea24941c26a48f2cec24e0bb0e8cc7
│       │   └── c8/
│       │       └── 306ae139ac98f432932286151dc0ec55580eca
│       └── Caches/
│           └── ...    <- iOS manages this
```

---

## 6. Summary

| Feature | Status | Solution |
|---------|--------|----------|
| Song Playback | ✅ Working | Location Kind=42, Base Location=3840 |
| Song Visibility | ✅ Working | item_store entry required |
| Queue/Navigation | ✅ Working | sort_map for all strings |
| **Song Artwork** | ✅ Working | SHA1(token) path + correct DB entries |
| **Album Artwork** | ✅ Working | entity_type=4 + ColorAnalysis + empty fetchable |
| Integrity Bypass | ✅ Working | Location Kind=42 |
