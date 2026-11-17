# complete

Every module-level input, shaped like a web fleet behind an ALB:

| Area | Shows |
|---|---|
| Instance mix | Four types with a weight, two on-demand instances always, then 25% on-demand and the rest Spot (`price-capacity-optimized`) |
| Scaling | Target tracking on CPU, ALB requests per target and an SQS backlog; predictive scaling in `ForecastOnly`; business-hours scheduled actions in London time |
| Replacement | Instance refresh in two checkpoints with rollback on an alarm; a maintenance policy that launches before it terminates; instances replaced after 14 days |
| Hooks | An `initial` launch hook that also holds the first instances, and a terminating hook that drains through SQS |
| Security | Every volume under a customer key, admitted for a custom-suffix service-linked role; no SSH key; IMDSv2 with hop limit 1; an instance role with Session Manager, an inline policy and a managed one, under a permissions boundary |
| Signals | Alarms and event rules on the topic, which is itself encrypted |

What fails in it: the ARNs are placeholders, so it plans (CI plans it against
a mocked provider) and would fail at apply.
