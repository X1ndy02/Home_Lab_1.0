Fail2Ban Implementation

System view
- protects SSH and web-facing authentication paths
- reacts to repeated failures instead of trying to sit inline in front of traffic
- tied into email notifications and a small monthly reporting flow

Fail2Ban is not treated as a standalone security product.

What interacts with what
- Nextcloud and nginx events come from application log files on the host
- jail filters evaluate those sources and raise ban decisions base on preset rules
- ban actions trigger firewall action 
- repeat offenders can be escalated by the recidive jail

Why this design
- host-level placement makes sense because it needs visibility across both system and application logs
- journal and file-based sources are both used because the protected services do not all log the same way
- email notifications were added so bans are visible without having to inspect the host manually and so unusual activity iis visible straight away
- recidive is enabled so repeated abuse is treated differently from one short burst of failures

This setup simple enough to operate, but still tied into the parts of the stack that matter most.

Flow
Event flow
- service emits authentication or access events
- Fail2Ban filter matches repeated bad behaviour
- the relevant jail counts failures inside its time window
- ban action is applied and notification is sent

Escalation flow
- repeat behaviour is written into Fail2Ban's own log
- recidive can ban more aggressively based on repeated offences over a longer period

Reporting flow
- a monthly cron job summarizes SSH failures and bans
- the summary is mailed out as an operational report

Trade-offs
- this is lighter than a larger security stack, but also much narrower
- it is effective for known log patterns, but only as good as the logs it can see
- it improves response to repeated abuse, but it does not replace better authentication design
- local network ignore rules reduce noise, but they also reduce visibility for trusted ranges

What is here
- [service_model.md](service_model.md): host/service boundary and how Fail2Ban fits into the system
- [jails.md](jails.md): the active jails, what they watch, and why they matter
- [issues_and_improvements.md](issues_and_improvements.md): current weak spots and next cleanup items
- `config/`: sanitized reference copy of the jail configuration
- `actions/`: custom action files used by this setup
- `reports/`: monthly reporting script and schedule reference
