# Security Policies

## Access control

- Grant least privilege and use named identities for human access.
- Require strong authentication for privileged operations.
- Separate production access from developer access.
- Review privileged membership periodically and remove access promptly when no longer required.
- Require server-side role and resource-level authorization for every protected operation.

## Secrets management

- Store secrets only in approved secret stores or protected environment injection.
- Never commit secrets or paste them into tickets, logs or source documentation.
- Rotate exposed or expired credentials; maintain a record of affected services.
- Use non-production credentials in development and staging.

## Data handling

- Collect only data needed for the stated business purpose.
- Classify personal, financial, authentication and operational data before sharing or logging.
- Restrict access by role and business need.
- Define retention/deletion rules and honor applicable legal obligations.
- Encrypt sensitive backups and protect their keys separately.

## Secure development

- Validate and normalize untrusted inputs.
- Use parameterized database operations.
- Keep dependencies patched and review vulnerability reports.
- Review authentication, authorization, tenant isolation and audit logging for every sensitive route.
- Protect uploads with size/type/signature validation and controlled storage.
- Avoid logging credentials, tokens, payment secrets or unnecessary personal data.

## Incident response

Report suspected credential exposure, unauthorized access, data loss or payment compromise immediately through the organization's approved security escalation channel. Preserve evidence, contain the incident, rotate affected credentials, assess scope, restore safely and document corrective actions. Do not invent or rely on contact details absent from the deployment's approved incident plan.

## Exceptions

Security exceptions must be documented with a business justification, scope, owner, compensating controls, expiry date and explicit approval. An exception must not silently become a permanent default.
