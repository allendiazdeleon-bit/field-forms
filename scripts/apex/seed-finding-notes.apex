/**
 * Backfills realistic observation + corrective-action feedback onto BK findings
 * that have a blank Notes__c, so the summary card / portal reads like real
 * inspector feedback instead of just the question text. Re-runnable: only
 * touches findings whose Notes__c is blank (leaves the curated seal notes
 * and any real captured feedback alone).
 */
String BRAND = 'BURGER_KING';

// Per-question feedback variants (observation + corrective action). Cycled by
// index so 56 "floor drain" findings don't all read identically.
Map<String, List<String>> byQuestion = new Map<String, List<String>>{
    'Are floor drains clean and free of residue?' => new List<String>{
        'Grease residue and standing water observed at the cook-line floor drain. Drain cleared and degreased during visit; added to nightly deep-clean checklist.',
        'Floor drain near the dish pit was slow to clear with visible buildup. Recommended enzyme treatment weekly and verify drain covers are seated.',
        'Light residue around prep-area drains. Cleaned on-site; coach team on squeegee-to-drain after each shift.'
    },
    'Is there any evidence of pest activity?' => new List<String>{
        'Two gnats observed near the dry-storage door; no nesting or droppings found. Sealed door sweep gap and scheduled pest-control follow-up.',
        'Evidence of a small ant trail along the back-prep baseboard. Treated and cleaned; monitor and confirm bait stations are current.',
        'Minor fruit-fly activity near the beverage station. Cleaned drip trays and floor drain; recommend daily wipe-down of syrup lines.'
    },
    'Are handwash stations stocked and accessible?' => new List<String>{
        'Soap dispenser at the prep-line handwash station was empty and a box was blocking access. Restocked and cleared the area; added to daily-open checklist.',
        'Paper towels out at the front handwash sink. Restocked during visit; assign a shift owner to verify stock at each changeover.',
        'Handwash sink near the grill was partially blocked by a mop bucket. Relocated bucket and re-briefed team on keeping sinks clear.'
    },
    'Are cold-holding temperature logs current?' => new List<String>{
        'Cold-holding log had gaps on the prior weekend shifts. Reviewed with the manager; set a recurring reminder and assigned weekend log ownership.',
        'Two missing temperature entries on the walk-in log. Back-checked unit at 38°F (in range); re-trained staff on twice-daily logging.',
        'Log current but last reading taken late. Reinforced the logging window and posted the schedule at the station.'
    },
    'Are food-contact surfaces sanitized per schedule?' => new List<String>{
        'Slicer contact surfaces showed light buildup at inspection. Broken down and sanitized on-site; verify the 4-hour sanitation cycle is being followed.',
        'Prep-table sanitizer bucket tested below concentration. Re-mixed to spec and re-trained on test-strip checks each shift.',
        'Cutting boards showed scoring and residue. Resurfaced/replaced affected boards and confirmed sanitation logbook is current.'
    },
    'Exterior and entry area clean' => new List<String>{
        'Litter and a full waste bin at the customer entry. Cleared during visit; added an hourly exterior walk to the shift checklist.',
        'Entry glass and door handles showed smudging. Cleaned on-site; assign opening crew to wipe-down before peak.',
        'Cigarette debris near the patio entrance. Cleaned and recommended a covered receptacle relocation.'
    }
};

List<Form_Finding__c> recs = [
    SELECT Id, Notes__c, Form_Question_Catalog__r.Question__c
    FROM Form_Finding__c
    WHERE Linked_Form__r.Form_Template__r.Scope__c LIKE :(BRAND + '%')
];

Map<String, Integer> cursor = new Map<String, Integer>();
List<Form_Finding__c> updates = new List<Form_Finding__c>();
Integer skipped = 0;
for (Form_Finding__c f : recs) {
    if (String.isNotBlank(f.Notes__c)) { skipped++; continue; } // keep existing
    String q = f.Form_Question_Catalog__r != null ? f.Form_Question_Catalog__r.Question__c : null;
    List<String> variants = q != null ? byQuestion.get(q) : null;
    if (variants == null || variants.isEmpty()) {
        // Generic fallback for any question without a tailored list.
        f.Notes__c = 'Issue observed at inspection. Corrective action taken on-site; '
            + 'item added to the store follow-up checklist for verification next visit.';
    } else {
        Integer i = cursor.containsKey(q) ? cursor.get(q) : 0;
        f.Notes__c = variants[Math.mod(i, variants.size())];
        cursor.put(q, i + 1);
    }
    updates.add(f);
}
update updates;
System.debug(LoggingLevel.ERROR, '\nBackfilled finding notes: updated=' + updates.size()
    + ' | left existing=' + skipped + ' | total=' + recs.size());
