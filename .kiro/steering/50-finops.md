---
inclusion: fileMatch
fileMatchPattern: "modules/**"
---

# FinOps expectations

Cost allocation is a prerequisite for the AWS funding work attached to this
estate, not a nice-to-have. Two consequences for module code:

- **Every billable resource must be attributable.** If a module launches
  something transient (a build instance, a Spot worker), it gets its own
  resource tags — otherwise it is anonymous in Cost Explorer and invisible to
  tag-based SCPs. `var.tags` on the module's own resources is not the same
  variable as tags on the transient thing it launches or the artifact it
  produces; keep them separate and document which is which.
- **Name the growing line.** For each module, identify the cost that grows
  without bound if nobody intervenes (retained snapshots, log retention, idle
  capacity, cross-region copies) and give it a default that bounds it. A
  retention policy that deprecates but never deletes costs nothing and saves
  nothing.

When adding a knob that costs money, put the number in its `description` — the
person setting it is the person who should see the price. Deeper analysis goes
in the module's `COSTS.md`.
