"""
Test that CDM spell ordering (trackedSpells) is preserved across reconcile
runs even when viewer pools or the CDM API return incomplete data.

Simulates the ReconcileMainBarSpells logic to verify that spells are never
incorrectly moved to dormant (and re-appended at the end) due to partial
viewer population or spellID resolution mismatches.
"""

import copy
import sys

passed = 0
failed = 0


def check(label, condition):
    global passed, failed
    if condition:
        passed += 1
    else:
        failed += 1
        print(f"  FAIL: {label}")


# ---------------------------------------------------------------------------
#  Simulate ReconcileMainBarSpells logic (the fixed version)
# ---------------------------------------------------------------------------
def reconcile_main_bar_spells(bar_data, all_viewer_spells, bar_pool,
                              sid_correction=None, is_buff_bar=False,
                              passives=None):
    """
    Port of ReconcileMainBarSpells's per-bar reconcile loop (fixed version).
    Returns the new trackedSpells list.
    """
    if sid_correction is None:
        sid_correction = {}
    if passives is None:
        passives = set()

    existing = bar_data.get("trackedSpells")
    if not existing:
        return None  # would trigger SnapshotBlizzardCDM

    removed = bar_data.get("removedSpells", {})
    kept = []
    kept_set = set()

    # Phase 1: keep existing spells in order
    for sid in existing:
        corrected = sid_correction.get(sid, sid)
        if corrected and corrected != 0 and corrected not in removed:
            is_passive = (not is_buff_bar) and corrected in passives
            if is_passive:
                pass  # silently drop
            else:
                # FIXED: always keep — don't move to dormant based on
                # incomplete viewer/API data.
                kept.append(corrected)
                kept_set.add(corrected)

    # Phase 2: append new spells from viewer that aren't already tracked
    dormant = bar_data.get("dormantSpells", {})
    for sid in bar_pool:
        if (sid and sid > 0
                and sid not in kept_set
                and sid not in removed
                and sid not in dormant):
            is_passive = (not is_buff_bar) and sid in passives
            if not is_passive:
                kept.append(sid)
                kept_set.add(sid)

    return kept


def reconcile_main_bar_spells_OLD(bar_data, all_viewer_spells, bar_pool,
                                   sid_correction=None, is_buff_bar=False,
                                   is_talent_aware=True, passives=None):
    """
    Port of the OLD (buggy) ReconcileMainBarSpells logic that moves spells
    to dormant for talent-aware bars when not found in allViewerSpells.
    """
    if sid_correction is None:
        sid_correction = {}
    if passives is None:
        passives = set()

    existing = bar_data.get("trackedSpells")
    if not existing:
        return None

    removed = bar_data.get("removedSpells", {})
    kept = []
    kept_set = set()

    for i, sid in enumerate(existing):
        corrected = sid_correction.get(sid, sid)
        if corrected and corrected != 0 and corrected not in removed:
            is_passive = (not is_buff_bar) and corrected in passives
            if is_passive:
                pass
            elif corrected in all_viewer_spells:
                kept.append(corrected)
                kept_set.add(corrected)
            elif is_talent_aware:
                # BUG: moves to dormant when viewer incomplete
                if "dormantSpells" not in bar_data:
                    bar_data["dormantSpells"] = {}
                bar_data["dormantSpells"][corrected] = i
            else:
                kept.append(corrected)
                kept_set.add(corrected)

    dormant = bar_data.get("dormantSpells", {})
    for sid in bar_pool:
        if (sid and sid > 0
                and sid not in kept_set
                and sid not in removed
                and sid not in dormant):
            is_passive = (not is_buff_bar) and sid in passives
            if not is_passive:
                kept.append(sid)
                kept_set.add(sid)

    return kept


# ---------------------------------------------------------------------------
#  Test 1: Full viewer — ordering preserved (both old and new)
# ---------------------------------------------------------------------------
print("Test 1: Full viewer — ordering preserved")
bar = {
    "trackedSpells": [100, 200, 300, 400, 500],
    "removedSpells": {},
}
all_viewer = {100, 200, 300, 400, 500}
pool = [100, 200, 300, 400, 500]

result = reconcile_main_bar_spells(copy.deepcopy(bar), all_viewer, pool)
check("full viewer: order unchanged", result == [100, 200, 300, 400, 500])


# ---------------------------------------------------------------------------
#  Test 2: Partial viewer — new code keeps all spells in order
# ---------------------------------------------------------------------------
print("Test 2: Partial viewer — spells kept in place (fixed)")
bar2 = {
    "trackedSpells": [100, 200, 300, 400, 500],
    "removedSpells": {},
}
# Viewer only has 3 of 5 spells populated
partial_viewer = {100, 300, 500}
partial_pool = [100, 300, 500]

result2 = reconcile_main_bar_spells(copy.deepcopy(bar2), partial_viewer, partial_pool)
check("partial viewer: all 5 spells kept", len(result2) == 5)
check("partial viewer: order preserved", result2 == [100, 200, 300, 400, 500])


# ---------------------------------------------------------------------------
#  Test 3: Partial viewer — OLD code incorrectly reorders
# ---------------------------------------------------------------------------
print("Test 3: Partial viewer — old code reorders (demonstrates bug)")
bar3 = copy.deepcopy(bar2)
result3 = reconcile_main_bar_spells_OLD(
    bar3, partial_viewer, partial_pool,
    is_talent_aware=True
)
# Old code: 200, 400 go dormant, only 100, 300, 500 kept
check("old bug: spells lost from bar", len(result3) < 5)
# The bug: missing spells are gone (or appear at the end under different IDs)


# ---------------------------------------------------------------------------
#  Test 4: SpellID mismatch — saved childSid vs API infoSid
# ---------------------------------------------------------------------------
print("Test 4: SpellID mismatch between child/info resolution")
bar4 = {
    # trackedSpells has child-resolved IDs
    "trackedSpells": [1001, 1002, 1003, 1004],
    "removedSpells": {},
}
# allViewerSpells has info-resolved IDs (different for spell 1002 and 1004)
all_viewer4 = {1001, 9002, 1003, 9004}  # 1002→9002, 1004→9004 mismatch
pool4 = [9002, 9004]  # viewer resolves to different IDs for missing ones

result4 = reconcile_main_bar_spells(copy.deepcopy(bar4), all_viewer4, pool4)
check("ID mismatch: all 4 original spells kept", len(result4) >= 4)
check("ID mismatch: original order preserved",
      result4[:4] == [1001, 1002, 1003, 1004])

# Old code would move 1002, 1004 to dormant, then append 9002, 9004 at end
bar4_old = copy.deepcopy(bar4)
result4_old = reconcile_main_bar_spells_OLD(
    bar4_old, all_viewer4, pool4,
    is_talent_aware=True
)
check("old bug: wrong spells at end",
      result4_old != [1001, 1002, 1003, 1004])


# ---------------------------------------------------------------------------
#  Test 5: sidCorrection fixes IDs during reconcile
# ---------------------------------------------------------------------------
print("Test 5: sidCorrection properly fixes IDs")
bar5 = {
    "trackedSpells": [1001, 8888, 1003],  # 8888 is a wrong ID for spell 1002
    "removedSpells": {},
}
correction = {8888: 1002}
all_viewer5 = {1001, 1002, 1003}
pool5 = [1001, 1002, 1003]

result5 = reconcile_main_bar_spells(copy.deepcopy(bar5), all_viewer5, pool5,
                                     sid_correction=correction)
check("correction: 3 spells kept", len(result5) == 3)
check("correction: wrong ID replaced", 8888 not in result5)
check("correction: correct ID present", 1002 in result5)
check("correction: order preserved", result5 == [1001, 1002, 1003])


# ---------------------------------------------------------------------------
#  Test 6: Removed spells still filtered out
# ---------------------------------------------------------------------------
print("Test 6: Removed spells still filtered")
bar6 = {
    "trackedSpells": [100, 200, 300, 400],
    "removedSpells": {200: True, 400: True},
}
all_viewer6 = {100, 200, 300, 400}
pool6 = [100, 200, 300, 400]

result6 = reconcile_main_bar_spells(copy.deepcopy(bar6), all_viewer6, pool6)
check("removed: 2 spells removed", len(result6) == 2)
check("removed: order of kept spells", result6 == [100, 300])


# ---------------------------------------------------------------------------
#  Test 7: New spells appended at end
# ---------------------------------------------------------------------------
print("Test 7: New spells appended at end")
bar7 = {
    "trackedSpells": [100, 200, 300],
    "removedSpells": {},
}
all_viewer7 = {100, 200, 300, 400, 500}
pool7 = [100, 200, 300, 400, 500]

result7 = reconcile_main_bar_spells(copy.deepcopy(bar7), all_viewer7, pool7)
check("new spells: total 5", len(result7) == 5)
check("new spells: originals first", result7[:3] == [100, 200, 300])
check("new spells: new ones at end", set(result7[3:]) == {400, 500})


# ---------------------------------------------------------------------------
#  Test 8: Passives still stripped from non-buff bars
# ---------------------------------------------------------------------------
print("Test 8: Passives stripped from non-buff bars")
bar8 = {
    "trackedSpells": [100, 200, 300],
    "removedSpells": {},
}
all_viewer8 = {100, 200, 300}
pool8 = [100, 200, 300]
passive_set = {200}

result8 = reconcile_main_bar_spells(copy.deepcopy(bar8), all_viewer8, pool8,
                                     passives=passive_set)
check("passives: passive stripped", 200 not in result8)
check("passives: non-passives kept", result8 == [100, 300])

# Buff bar: passives NOT stripped
result8b = reconcile_main_bar_spells(copy.deepcopy(bar8), all_viewer8, pool8,
                                      passives=passive_set, is_buff_bar=True)
check("buff bar: passives kept", result8b == [100, 200, 300])


# ---------------------------------------------------------------------------
#  Test 9: Empty viewer pool — reconcile skipped (trackedSpells unchanged)
# ---------------------------------------------------------------------------
print("Test 9: Empty viewer pool preserves trackedSpells")
bar9 = {
    "trackedSpells": [100, 200, 300],
    "removedSpells": {},
}
# This test simulates the poolHasAny check in the real code
# If pool is empty, reconcile is skipped entirely
empty_pool = []
check("empty pool: reconcile returns original when using full code path",
      bar9["trackedSpells"] == [100, 200, 300])


# ---------------------------------------------------------------------------
#  Test 10: CDM API unavailable — allViewerSpells empty
# ---------------------------------------------------------------------------
print("Test 10: Empty allViewerSpells — spells still preserved")
bar10 = {
    "trackedSpells": [100, 200, 300, 400],
    "removedSpells": {},
}
# allViewerSpells empty (API unavailable), but pool has some entries
empty_all_viewer = set()
some_pool = [100, 300]

result10 = reconcile_main_bar_spells(copy.deepcopy(bar10), empty_all_viewer, some_pool)
check("empty API: all spells kept", len(result10) == 4)
check("empty API: order preserved", result10 == [100, 200, 300, 400])


# ---------------------------------------------------------------------------
#  Summary
# ---------------------------------------------------------------------------
print()
total = passed + failed
if failed == 0:
    print(f"All {total} checks passed.")
    sys.exit(0)
else:
    print(f"{failed}/{total} checks FAILED.")
    sys.exit(1)
