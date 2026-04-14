# Security Guide - POS System

## 🔐 Security Features Implemented

### 1. Database Encryption (Mobile)
- **SQLCipher** encryption for SQLite database
- 256-bit AES encryption key stored in secure storage (iOS Keychain / Android Keystore)
- Automatic key backup and rotation support

### 2. Authentication Hardening (Backend)
- **Cryptographically secure refresh tokens** (64 bytes random)
- **Token hashing** - refresh tokens stored as SHA-256 hashes
- **Device fingerprinting** - detects token theft
- **Login attempt throttling** - 5 attempts, 30-minute lockout
- **JWT with unique ID (jti)** - enables token revocation

### 3. Secrets Management
- Docker Secrets support for production
- No hardcoded credentials
- `_FILE` suffix pattern for secret loading

### 4. Password Security
- bcrypt with cost factor 12
- Minimum 8 character password requirement
- PIN validation (4-6 digits only)

---

## 🚀 Setup Instructions

### Development Environment

1. **Generate secure secrets:**
   ```bash
   # Backend
   node scripts/generate-secrets.js
   
   # Copy output to backend/.env and store-management-system/.env
   ```

2. **Update .env files with generated values**

3. **Never commit .env files:**
   ```bash
   git add .gitignore
   git commit -m "Configure secure environment"
   ```

### Production Environment

1. **Initialize Docker secrets:**
   ```bash
   chmod +x scripts/init-secrets.sh
   ./scripts/init-secrets.sh
   ```

2. **Update payment provider credentials:**
   ```bash
   # Edit files in ./secrets/ with real credentials
   nano secrets/daraja_consumer_key
   nano secrets/daraja_consumer_secret
   # ... etc
   ```

3. **Deploy with secrets:**
   ```bash
   docker stack deploy -c docker-compose.prod.yml pos
   ```

---

## 📋 Security Checklist

### Before Going Live

- [ ] Replace all placeholder secrets with production values
- [ ] Enable HTTPS/TLS (SSL certificates in `nginx/ssl/`)
- [ ] Configure firewall rules (only ports 80/443 open)
- [ ] Set up automated database backups
- [ ] Configure log aggregation and security monitoring
- [ ] Enable rate limiting (configured in `docker-compose.prod.yml`)
- [ ] Set up intrusion detection (fail2ban, etc.)
- [ ] Configure CORS properly for your domain
- [ ] Test payment webhooks in production mode

### Ongoing Maintenance

- [ ] Rotate JWT secrets every 90 days
- [ ] Rotate database passwords every 90 days
- [ ] Review audit logs weekly
- [ ] Monitor failed login attempts
- [ ] Keep dependencies updated (`npm audit`, `flutter pub outdated`)
- [ ] Review and update security policies quarterly

---

## 🛡️ Security Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    INTERNET                                  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                   NGINX (TLS Termination)                    │
│  - Rate limiting                                             │
│  - Request validation                                        │
│  - SSL/TLS encryption                                        │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                  BACKEND API (NestJS)                        │
│  - JWT Authentication (15min expiry)                         │
│  - Refresh token rotation (7 days)                           │
│  - Device fingerprinting                                     │
│  - Login throttling                                          │
│  - Password hashing (bcrypt-12)                              │
└─────────────────────────────────────────────────────────────┘
                            │
            ┌───────────────┼───────────────┐
            ▼               ▼               ▼
    ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
    │  PostgreSQL  │ │    Redis     │ │   Audit      │
    │  (TLS)       │ │  (Password)  │ │   Logs       │
    └──────────────┘ └──────────────┘ └──────────────┘
```

---

## 📱 Mobile Security

### Encryption at Rest
- All local SQLite data encrypted with SQLCipher
- Encryption key stored in platform secure storage
- Key backup for recovery

### Network Security
- Certificate pinning recommended for production
- HTTPS-only communication
- JWT token in Authorization header

### Best Practices
- Enable biometric authentication for app access
- Implement session timeout (auto-logout)
- Clear sensitive data on logout

---

## 🚨 Incident Response

### If Credentials Are Compromised

1. **Immediately rotate all secrets:**
   ```bash
   rm -rf secrets/
   ./scripts/init-secrets.sh
   ```

2. **Revoke all active sessions:**
   ```bash
   # This invalidates all refresh tokens
   npm run revoke-all-tokens
   ```

3. **Force password reset for all users**

4. **Review audit logs for suspicious activity**

5. **Deploy updated secrets and restart services**

### If Database Is Compromised

1. Refresh tokens are hashed - not usable even if DB leaked
2. Password hashes use bcrypt-12 - computationally expensive to crack
3. Force password reset for all users as precaution

---

## 🔍 Security Monitoring

### Key Metrics to Track

| Metric | Alert Threshold |
|--------|-----------------|
| Failed logins per IP | > 10/hour |
| Failed logins per user | > 5/30min |
| Token refresh failures | > 20/hour |
| 4xx/5xx error rate | > 5% |
| Response time p99 | > 2s |

### Log Files to Monitor

- `nginx/logs/access.log` - HTTP requests
- `nginx/logs/error.log` - Server errors
- Backend application logs
- PostgreSQL logs
- Redis logs

---

## 📚 References

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [NestJS Security Best Practices](https://docs.nestjs.com/security/overview)
- [Docker Secrets Documentation](https://docs.docker.com/engine/swarm/secrets/)
- [SQLCipher Documentation](https://www.zetetic.net/sqlcipher/)

---

## 📞 Security Contact

Report security vulnerabilities to: security@your-domain.com

**Do not** create public GitHub issues for security vulnerabilities.
