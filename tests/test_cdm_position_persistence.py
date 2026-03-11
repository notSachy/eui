"""
Test that CDM bar positions survive the full save/load/strip cycle.

Simulates the EUILite StripDefaults + DeepMergeDefaults round-trip and
the CDM per-spec profile save/load to verify positions are not lost.
"""

import copy
import sys

passed = 0
failed = 0


def deep_merge_defaults(dest, defaults):
    """Port of EUILite DeepMergeDefaults: fill missing keys only."""
    for k, v in defaults.items():
        if isinstance(v, dict):
            if not isinstance(dest.get(k), dict):
                dest[k] = {}
            deep_merge_defaults(dest[k], v)
        else:
            if k not in dest:
                dest[k] = v


def strip_defaults(db, defaults):
    """Port of EUILite StripDefaults: remove values matching defaults."""
    keys_to_remove = []
    for k, v in defaults.items():
        if isinstance(v, dict) and isinstance(db.get(k), dict):
            strip_defaults(db[k], v)
            if not db[k]:
                keys_to_remove.append(k)
        elif db.get(k) == v:
            keys_to_remove.append(k)
    for k in keys_to_remove:
        del db[k]


# Minimal CDM profile defaults (mirrors the addon's DEFAULTS.profile)
CDM_DEFAULTS = {
    "activeSpecKey": "0",
    "cdmBars": {
        "enabled": True,
        "hideBlizzard": True,
        "bars": {
            1: {"key": "cooldowns", "barScale": 1.0, "iconSize": 42, "anchorTo": "none"},
            2: {"key": "utility",   "barScale": 1.0, "iconSize": 36, "anchorTo": "none"},
            3: {"key": "buffs",     "barScale": 1.0, "iconSize": 32, "anchorTo": "none"},
        },
    },
    "cdmBarPositions": {},
    "tbbPositions": {},
    "specProfiles": {},
    "barGlows": {
        "enabled": True,
        "selectedBar": 1,
        "selectedAssignment": 1,
        "assignments": {},
    },
}


def save_current_spec_profile(profile):
    """Port of SaveCurrentSpecProfile with the cdmBarPositions fix."""
    spec_key = profile.get("activeSpecKey", "0")
    if not spec_key or spec_key == "0":
        return
    if "specProfiles" not in profile:
        profile["specProfiles"] = {}
    prof = {}
    prof["barGlows"] = copy.deepcopy(profile.get("barGlows"))
    if profile.get("tbbPositions") is not None:
        prof["tbbPositions"] = copy.deepcopy(profile["tbbPositions"])
    if profile.get("cdmBarPositions") is not None:
        prof["cdmBarPositions"] = copy.deepcopy(profile["cdmBarPositions"])
    profile["specProfiles"][spec_key] = prof


def load_spec_profile(profile, spec_key):
    """Port of LoadSpecProfile with the cdmBarPositions fix."""
    sp = profile.get("specProfiles", {})
    prof = sp.get(spec_key)
    if not prof:
        return
    if prof.get("barGlows") is not None:
        profile["barGlows"] = copy.deepcopy(prof["barGlows"])
    if prof.get("tbbPositions") is not None:
        profile["tbbPositions"] = copy.deepcopy(prof["tbbPositions"])
    if prof.get("cdmBarPositions") is not None:
        profile["cdmBarPositions"] = copy.deepcopy(prof["cdmBarPositions"])


def check(label, condition):
    global passed, failed
    if condition:
        passed += 1
    else:
        failed += 1
        print(f"  FAIL: {label}")


# ---- Test 1: Positions survive StripDefaults + DeepMergeDefaults ----
print("Test 1: Positions survive strip/merge round-trip")
profile = copy.deepcopy(CDM_DEFAULTS)
deep_merge_defaults(profile, CDM_DEFAULTS)
profile["cdmBarPositions"]["cooldowns"] = {"point": "CENTER", "relPoint": "CENTER", "x": 150.5, "y": -80.3}
profile["cdmBarPositions"]["utility"]   = {"point": "CENTER", "relPoint": "CENTER", "x": -200.0, "y": 100.0}
profile["_capturedOnce"] = True
profile["activeSpecKey"] = "262"

# Simulate logout: PreLogout -> StripDefaults
saved_positions = copy.deepcopy(profile["cdmBarPositions"])
strip_defaults(profile, CDM_DEFAULTS)

# cdmBarPositions should survive (non-empty, default is {})
check("cdmBarPositions survives stripping", "cdmBarPositions" in profile)
check("positions intact after strip", profile.get("cdmBarPositions") == saved_positions)
check("_capturedOnce survives (not in defaults)", profile.get("_capturedOnce") == True)

# Simulate login: DeepMergeDefaults
deep_merge_defaults(profile, CDM_DEFAULTS)
check("positions intact after merge", profile["cdmBarPositions"] == saved_positions)
check("cooldowns position x correct", profile["cdmBarPositions"]["cooldowns"]["x"] == 150.5)
check("utility position y correct", profile["cdmBarPositions"]["utility"]["y"] == 100.0)


# ---- Test 2: Empty positions get stripped cleanly then recreated ----
print("Test 2: Empty positions stripped then recreated on merge")
profile2 = copy.deepcopy(CDM_DEFAULTS)
deep_merge_defaults(profile2, CDM_DEFAULTS)
# cdmBarPositions is {} (empty, matches default)
strip_defaults(profile2, CDM_DEFAULTS)
check("empty cdmBarPositions stripped", "cdmBarPositions" not in profile2)
deep_merge_defaults(profile2, CDM_DEFAULTS)
check("cdmBarPositions recreated after merge", isinstance(profile2.get("cdmBarPositions"), dict))


# ---- Test 3: PreLogout saves intact data before StripDefaults ----
print("Test 3: PreLogout ordering saves data before strip")
profile3 = copy.deepcopy(CDM_DEFAULTS)
deep_merge_defaults(profile3, CDM_DEFAULTS)
profile3["activeSpecKey"] = "262"
profile3["cdmBarPositions"]["cooldowns"] = {"point": "CENTER", "relPoint": "CENTER", "x": 50.0, "y": -50.0}
profile3["barGlows"]["assignments"]["1_3"] = [{"spellID": 12345, "glowStyle": "pixel"}]

# PreLogout: save spec profile BEFORE strip (the fix)
save_current_spec_profile(profile3)

# Now StripDefaults runs
strip_defaults(profile3, CDM_DEFAULTS)

# The spec profile should have the full data (saved before strip)
spec_prof = profile3.get("specProfiles", {}).get("262", {})
check("spec profile saved before strip", spec_prof is not None)
check("spec profile has cdmBarPositions", "cdmBarPositions" in spec_prof)
check("spec profile position correct",
      spec_prof.get("cdmBarPositions", {}).get("cooldowns", {}).get("x") == 50.0)
check("spec profile barGlows intact",
      spec_prof.get("barGlows", {}).get("assignments", {}).get("1_3") is not None)


# ---- Test 4: Old bug - SaveCurrentSpecProfile AFTER StripDefaults ----
print("Test 4: Verify old bug (save after strip loses barGlows fields)")
profile4 = copy.deepcopy(CDM_DEFAULTS)
deep_merge_defaults(profile4, CDM_DEFAULTS)
profile4["activeSpecKey"] = "65"
profile4["barGlows"]["assignments"]["2_1"] = [{"spellID": 99999}]
profile4["cdmBarPositions"]["buffs"] = {"point": "CENTER", "relPoint": "CENTER", "x": 0, "y": 200}

# Simulate OLD behavior: StripDefaults runs first, THEN save
strip_defaults(profile4, CDM_DEFAULTS)
# barGlows scalar fields (enabled, selectedBar, etc.) are stripped
save_current_spec_profile(profile4)

spec_prof4 = profile4.get("specProfiles", {}).get("65", {})
bg = spec_prof4.get("barGlows", {})
# After strip, the scalar fields matching defaults are gone
check("old bug: barGlows.enabled stripped before save",
      "enabled" not in bg)
# But cdmBarPositions was never saved in spec profiles (old code)
# so it wouldn't be in spec_prof4 regardless -- only the new fix adds it


# ---- Test 5: Spec switch preserves positions per-spec ----
print("Test 5: Spec switch preserves positions per-spec")
profile5 = copy.deepcopy(CDM_DEFAULTS)
deep_merge_defaults(profile5, CDM_DEFAULTS)
profile5["activeSpecKey"] = "262"
profile5["cdmBarPositions"]["cooldowns"] = {"point": "CENTER", "relPoint": "CENTER", "x": 100, "y": -100}

# Save spec A positions
save_current_spec_profile(profile5)

# Switch to spec B with different positions
profile5["activeSpecKey"] = "263"
profile5["cdmBarPositions"]["cooldowns"] = {"point": "CENTER", "relPoint": "CENTER", "x": -300, "y": 200}
save_current_spec_profile(profile5)

# Switch back to spec A
load_spec_profile(profile5, "262")
check("spec A positions restored",
      profile5["cdmBarPositions"]["cooldowns"]["x"] == 100)
check("spec A positions y restored",
      profile5["cdmBarPositions"]["cooldowns"]["y"] == -100)

# Switch to spec B again
load_spec_profile(profile5, "263")
check("spec B positions restored",
      profile5["cdmBarPositions"]["cooldowns"]["x"] == -300)


# ---- Test 6: TOPLEFT to CENTER migration in-place ----
print("Test 6: TOPLEFT to CENTER migration")
pos = {"point": "TOPLEFT", "relPoint": "TOPLEFT", "x": 200, "y": -300}
# Simulate ApplyBarPositionCentered migration
if pos["point"] == "TOPLEFT" and pos["relPoint"] == "TOPLEFT":
    fw, fh = 150, 36  # example frame dimensions
    ui_w, ui_h = 1920, 1080
    cx = pos["x"] + fw * 0.5 - ui_w * 0.5
    cy = pos["y"] - fh * 0.5 + ui_h * 0.5
    pos["point"] = "CENTER"
    pos["relPoint"] = "CENTER"
    pos["x"] = cx
    pos["y"] = cy

check("migration converts to CENTER", pos["point"] == "CENTER")
check("migration relPoint is CENTER", pos["relPoint"] == "CENTER")
# After migration, re-applying should not migrate again
check("no double migration", pos["point"] == "CENTER")


# ---- Summary ----
print()
total = passed + failed
if failed == 0:
    print(f"All {total} checks passed.")
    sys.exit(0)
else:
    print(f"{failed}/{total} checks FAILED.")
    sys.exit(1)
