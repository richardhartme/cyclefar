# Rider account access

Riders register from the public homepage (email and confirmed password) and are signed in straight away. An operator can also provision an account by email; that rider sets a password through the emailed link. Live SMTP delivery has not been verified, so operator provisioning stays disabled until it has been.

## Production mail settings

Set these before sending any invitation or reset email:

| Variable | Purpose |
|---|---|
| `CYCLEFAR_APP_HOST` | Public HTTPS host for password links, without scheme or path. |
| `CYCLEFAR_MAIL_FROM` | Sender address authorized by the SMTP provider. |
| `CYCLEFAR_SMTP_HOST` | SMTP server address. |
| `CYCLEFAR_SMTP_PORT` | SMTP port; defaults to `587`. |
| `CYCLEFAR_SMTP_USERNAME` | SMTP username. |
| `CYCLEFAR_SMTP_PASSWORD` | SMTP password or provider token. |

- Production uses authenticated SMTP with STARTTLS and raises delivery errors. Missing required settings stop production boot.
- Keep the SMTP password in a secret store; never commit it.
- Password-reset mail goes through Active Job, so the Solid Queue worker must run. Kamal sets `SOLID_QUEUE_IN_PUMA=true`, so `config/puma.rb` starts it inside the web container.
- Provisioning sends its setup email immediately and rolls back the new account if delivery fails.

With Kamal, `config/deploy.yml` sets `CYCLEFAR_APP_HOST=cyclefar.com` and the default port. Export `CYCLEFAR_MAIL_FROM`, `CYCLEFAR_SMTP_HOST`, `CYCLEFAR_SMTP_USERNAME` and `CYCLEFAR_SMTP_PASSWORD` in the deploy shell (`.kamal/secrets` reads them), or replace those entries with password-manager lookups. The Docker asset build boots Rails with temporary, non-secret mail values.

## Production encryption keys

Production also needs `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` and `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`.

1. Generate one set with `bin/rails db:encryption:init` and store it in a secret manager.
2. Export the values in the deploy shell; Kamal passes them through `.kamal/secrets`.
3. Run `bin/kamal app boot` so the container picks up the new environment.

Keep this set for as long as encrypted Intervals.icu API keys exist; replacing it makes them unreadable.

## Testing

Tests use Action Mailer's test adapter. Request specs cover the delivered link, account setup, identical reset responses for known and unknown addresses, and invalidation of old sessions. They don't prove delivery through a live provider: check that before enabling more riders.

## Provision a rider

Run in the deployed environment:

```bash
CYCLEFAR_RIDER_PROVISIONING_ENABLED=true EMAIL_ADDRESS=rider@example.test bin/rails accounts:provision
```

The task creates one `User` with a random password, emails a short-lived setup link and prints the normalized address. It rejects invalid or existing addresses. Confirm delivery with the rider; if it fails, fix the mail configuration and retry (the account is rolled back). Riders can request another link through **Forgot password?**.

Signing out destroys the database session and clears the browser's Rails session, including any plan preview draft.
