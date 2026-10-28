# data-lake

A customer key, `raw/` tiered to Standard-IA then Glacier, `scratch/` expiring
after two weeks, read access to `curated/` for a role in an analytics account,
object access only from within the organization, replication to a DR region
with Replication Time Control, and a weekly inventory.

Before the first apply: both key owners need
`output.kms_key_policy_requirements`, and the DR bucket's owner
`output.replication_destination_requirements` and the inventory statement.
