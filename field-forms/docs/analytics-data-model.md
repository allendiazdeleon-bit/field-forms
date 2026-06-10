# Field Forms — Analytics Data Model (for the Tableau layer)

The star schema a Tableau builder needs, in one page. All objects connect
via standard Salesforce lookups; everything below is queryable through the
Salesforce/Data Cloud connector with no staging required.

## Fact tables

### Inspection fact — `Linked_Form__c` (grain: one inspection visit)
| Measure / fact | Field | Notes |
|---|---|---|
| Score / max / percent / passed | `Score__c`, `Max_Score__c`, `Score_Percent__c`, `Passed__c` | Written by the scoring engine at answer save |
| Findings open / blocking | `Findings_Open_Count__c`, `Findings_Blocking_Count__c` | Rollups, always current |
| Visit date | `Visit_Date__c` | Trigger-stamped at completion |
| Started / completed at | `Started_At__c`, `Completed_At__c` | Trigger-stamped at status transitions; durable (audit fields drift with later automation) |
| Fill duration (min) | `Fill_Duration_Minutes__c` | Stamped number — aggregate directly |
| Inspector | `Completed_By__c` → User | The inspector dimension |
| Signature audit | `Signed_By_Name__c`, `Signature_Captured_At__c`, `Signature_Latitude__c/Longitude__c` | Geo facts for map visuals |
| QC (future wave) | `Re_Roll__c`, `Inspector_Tenure_Months__c` | Reserved for the manager-QC wave |

Dimensions: `Account__c` (the branch), `Account__r.Form_Scope__c` (**the
brand** — the partition key, your top-level customer dimension),
`Form_Template__c` (the form), `Work_Order__c` / `Service_Appointment__c`
(FSL context).

### Finding fact — `Form_Finding__c` (grain: one issue found)
Severity (`Severity__c`), lifecycle (`Status__c`: Open → Resolved /
Resolved-Exception / Auto-Resolved / Waived), submit-blocking, photo
compliance (`Photo_Required__c` vs `Photo_Attached__c`), exception
reasons, assignment + due date. Joins: `Linked_Form__c` (→ branch, brand,
date) and `Form_Question_Catalog__c` (→ stable question identity).

### Answer fact — `Form_Answer__c` (grain: one answer)
`Answer__c` (text), `Passed__c`, `Points_Earned__c`, `Type__c`.
Joins: `Linked_Form__c`, `Form_Question__c` (per-template question) and
`Form_Question_Catalog__c` (stable identity, trigger-denormalized).

### Anomaly fact — `Anomaly_Alert__c` (grain: one detected pattern)
Pattern text, recurrence count, status, account, draft outreach.

## The one rule that keeps trends honest

**Always trend questions by `Form_Question_Catalog__c`, never by
`Form_Question__c`.** Per-template questions are new records every form
version; the catalog entry is the identity that survives revisions.
"Door-seal failures across all BK forms and years" only works at catalog
grain. (`Is_Curated__c` separates deliberate library entries from
auto-created scoring holders if you need to filter.)

## Example questions this model answers
- Average score by brand, by month → Inspection fact × `Form_Scope__c` × `Visit_Date__c`
- Top recurring findings across a brand's branches → Finding fact grouped by catalog entry, filtered to brand scope
- Remediation rate → Finding fact: Resolved* ÷ all, by brand/quarter
- Inspector workload & pace → Inspection fact: count + avg `Fill_Duration_Minutes__c` by `Completed_By__c`
- Photo compliance → Finding fact: `Photo_Attached__c` ÷ `Photo_Required__c`
