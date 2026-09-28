# Controlled rider account access

CycleFar has no public registration route. An authorized operator provisions an account by email, and the rider sets a password through the emailed link. The automated CYF-74 two-user isolation matrix has passed locally; keep rider provisioning disabled until the target-data migration rehearsal, live SMTP verification and open Milestone 11 acceptance gate pass. Existing single-rider access remains available.

## Production mail settings

Supply these environment variables in the intended production environment before sending an invitation or reset message:

| Variable | Purpose |
|---|---|
| `CYCLEFAR_APP_HOST` | Public HTTPS host for password links, without a scheme or path. |
| `CYCLEFAR_MAIL_FROM` | Sender address authorized by the SMTP provider. |
| `CYCLEFAR_SMTP_HOST` | SMTP server address. |
| `CYCLEFAR_SMTP_PORT` | SMTP port; defaults to `587`. |
| `CYCLEFAR_SMTP_USERNAME` | SMTP username. |
| `CYCLEFAR_SMTP_PASSWORD` | SMTP password or provider token. |

Production uses authenticated SMTP with STARTTLS, sends mail from `CYCLEFAR_MAIL_FROM`, and raises delivery errors. Missing required settings stop production boot. Keep the SMTP password in the environment's secret store; do not commit it. Password-reset requests enqueue mail through Active Job, so the Solid Queue worker must be running. Provisioning sends its setup email immediately and rolls back the new account if delivery fails.

The test environment uses Action Mailer's test delivery adapter. Request specs verify the delivered link, account setup, identical reset-request responses for known and unknown addresses, and invalidation of old sessions. These tests do not establish delivery through a live SMTP provider; check that with the configured provider before enabling additional riders.

## Provision a rider after the release gate

Run the task in the deployed environment with the provisioning flag and intended address:

```bash
CYCLEFAR_RIDER_PROVISIONING_ENABLED=true EMAIL_ADDRESS=rider@example.test bin/rails accounts:provision
```

The task creates one `User` with an unshared random password, emails a short-lived password setup link, and prints the normalized address. It rejects an invalid or existing address and does not expose a signup page. The operator should confirm mail delivery with the rider. If delivery fails, correct the mail configuration and retry; the failed account creation is rolled back. A rider can later request another link through **Forgot password?**. Sign-out destroys the active database session and clears the browser's Rails session, including any plan preview draft.
