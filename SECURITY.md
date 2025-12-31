# Security Policy

## Supported Versions

We provide security updates for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.2   | :white_check_mark: |
| 1.0.0   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

We take the security of pg_ttl_index seriously. If you believe you have found a security vulnerability, please report it to us as described below.

### Please DO NOT:

- Open a public GitHub issue for security vulnerabilities
- Discuss the vulnerability publicly before it has been addressed

### Please DO:

**Report security vulnerabilities by emailing:** ibrahimkarimeddin@gmail.com

Include the following information:
- Type of vulnerability
- Full paths of source file(s) related to the vulnerability
- Location of the affected source code (tag/branch/commit or direct URL)
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the vulnerability
- Any suggested remediation

### What to Expect:

1. **Acknowledgment:** We'll acknowledge receipt of your vulnerability report within 48 hours
2. **Communication:** We'll keep you informed about the progress of fixing the vulnerability
3. **Disclosure:** Once the vulnerability is fixed, we'll coordinate with you on public disclosure
4. **Credit:** We'll credit you in the security advisory (unless you prefer to remain anonymous)

## Security Considerations for Users

### Background Worker

The TTL background worker:
- Runs with the privileges of the user who started it
- Requires superuser privileges to start/stop
- Only processes databases where it's explicitly started
- Respects PostgreSQL's authentication and authorization

### SQL Injection Protection

All user-provided table and column names are properly quoted using `quote_literal_cstr()` to prevent SQL injection attacks.

### Permissions

- Extension installation requires superuser privileges
- TTL configuration modification requires appropriate table permissions
- Regular users can view TTL configurations but cannot modify them

### Best Practices

1. **Audit TTL Configurations:** Regularly review which tables have TTL configured
   ```sql
   SELECT * FROM ttl_summary();
   ```

2. **Monitor Worker Activity:** Check background worker status
   ```sql
   SELECT * FROM ttl_worker_status();
   ```

3. **Review Logs:** Monitor PostgreSQL logs for TTL-related warnings or errors

4. **Test Before Production:** Always test TTL configurations in a development environment first

5. **Backup Before Cleanup:** Ensure proper backups exist before enabling TTL on critical tables

## Known Security Considerations

### Data Loss Risk

TTL automatically **deletes** data. Ensure:
- Proper backups are in place
- TTL configurations are reviewed and approved
- Expire times are set correctly
- Test configurations in non-production environments

### Background Worker Privileges

The background worker runs with database-level privileges. Ensure:
- Only trusted users can start/stop workers
- Worker activity is monitored
- Appropriate PostgreSQL authentication is configured

## Security Updates

Security updates will be released as patch versions. Subscribe to:
- GitHub repository releases
- Security advisories on GitHub

## Compliance

This extension handles data deletion, which may have implications for:
- GDPR (General Data Protection Regulation)
- CCPA (California Consumer Privacy Act)
- SOC 2 compliance
- Industry-specific regulations

Consult with your legal and compliance teams to ensure TTL configurations align with your data retention policies.
