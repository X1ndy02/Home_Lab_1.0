Jail View

Active jails
- `sshd`
- `nextcloud`
- `nginx-http-auth`
- `nginx-botsearch`
- `recidive`

What each one is doing
`sshd`
- watches SSH-related failures from the system journal
- protects the host entry point directly
- matters because it is the most obvious remote management surface

`nextcloud`
- watches the application log for Nextcloud authentication or abuse patterns
- extends protection into the user-facing storage application
- depends on the application log path staying stable and readable

`nginx-http-auth`
- watches nginx error log authentication failures
- protects the web-facing access layer rather than the app logic itself
- helps catch abuse before it only appears deeper in the stack

`nginx-botsearch`
- watches nginx access log patterns tied to hostile or noisy probing
- gives broader visibility than only login failures
- depends heavily on the quality of access logging

`recidive`
- watches Fail2Ban's own log
- escalates repeated offending behaviour over a longer period
- gives the setup memory instead of treating every burst as isolated

How they interact
These jails are not equal. They sit at different points in the request path:
- SSH jail protects direct host access
- nginx jails protect the web entry layer
- Nextcloud jail protects the application layer
- recidive sits above them as a repeat-offender layer

That layering matters because it gives different ways to see the same hostile behaviour:
- a problem might show up first at nginx
- then later in the app log
- then eventually as repeated bans through recidive

Failure implications
- if journal-based detection breaks, SSH visibility drops first
- if app log paths change, the web/application jails become weaker even if Fail2Ban is still running
- if notification breaks, bans may still happen but operator awareness drops
- if recidive is missing, repeated abuse is treated too locally and too briefly
