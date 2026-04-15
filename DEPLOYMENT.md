# POS System Deployment Guide - Kamakunji Market

This guide covers the complete deployment process for the Hybrid Multi-Branch POS System designed for Kamakunji Market.

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Local Development Setup](#local-development-setup)
3. [Production Deployment](#production-deployment)
4. [POS Integration](#pos-integration)
5. [RBAC Configuration](#rbac-configuration)
6. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software

| Software | Version | Purpose |
|----------|---------|---------|
| Node.js | 18.x or 20.x | Backend & Store Management |
| Flutter | 3.x | Mobile POS App |
| PostgreSQL | 15.x | Database |
| Docker | 24.x | Containerization (production) |
| Git | Latest | Version control |

### Install Prerequisites (Windows)

```powershell
# Install Node.js
winget install OpenJS.NodeJS.LTS

# Install PostgreSQL
winget install PostgreSQL.PostgreSQL.15

# Install Docker Desktop
winget install Docker.DockerDesktop

# Install Flutter
winget install Flutter.Flutter
```

---

## Local Development Setup

### Step 1: Clone Repository

```bash
git clone <repository-url> pos-system
cd pos-system
```

### Step 2: Setup Store Management System

```bash
cd store-management-system

# Run database setup script
chmod +x scripts/setup-database.sh
./scripts/setup-database.sh

# Or manual setup:
# 1. Update .env with your database credentials
# 2. Install dependencies
npm install

# 3. Generate Prisma client
npx prisma generate

# 4. Run migrations
npx prisma migrate dev

# 5. Create admin user
node scripts/create-admin.js

# 6. Start development server
npm run dev
```

Access at: `http://localhost:3000`

### Step 3: Setup Backend API

```bash
cd backend

# Install dependencies
npm install

# Generate Prisma client
npx prisma generate

# Run migrations
npx prisma migrate dev

# Generate secure secrets
node ../scripts/generate-secrets.js

# Update backend/.env with generated secrets

# Start development server
npm run start:dev
```

API available at: `http://localhost:3000/api/v1`
Swagger docs at: `http://localhost:3000/api/docs`

### Step 4: Setup Mobile POS App

```bash
cd mobile

# Install dependencies
flutter pub get

# Generate code
flutter pub run build_runner build

# Update API URL in lib/core/network/api_client.dart
# Change API_URL to point to your backend

# Run on device/emulator
flutter run
```

---

## Production Deployment

### Option 1: Docker Compose (Recommended)

```bash
cd store-management-system

# 1. Create production .env file
cat > .env.production << EOF
DB_USER=store_user
DB_PASSWORD=<strong-password>
DB_NAME=store_db
NEXTAUTH_URL=https://your-domain.com
NEXTAUTH_SECRET=<64-char-random-string>
NEXT_PUBLIC_APP_NAME="Kamakunji Store Management"
EOF

# 2. Build and start containers
docker-compose --env-file .env.production up -d --build

# 3. Check logs
docker-compose logs -f

# 4. Run migrations
docker-compose exec web npx prisma migrate deploy

# 5. Create admin user
docker-compose exec web node scripts/create-admin.js
```

### Option 2: Manual Production Deployment

#### Backend Server

```bash
# Install dependencies
npm ci --production

# Generate Prisma client
npx prisma generate

# Run production migrations
npx prisma migrate deploy

# Build application
npm run build

# Start with PM2
pm2 start dist/main.js --name pos-backend
```

#### Store Management System

```bash
# Install dependencies
npm ci --production

# Build Next.js
npm run build

# Start with PM2
pm2 start npm --name store-web -- start
```

### SSL/TLS Configuration

```bash
# Generate SSL certificates (Let's Encrypt)
certbot certonly --standalone -d your-domain.com

# Copy certificates to nginx/ssl/
cp /etc/letsencrypt/live/your-domain.com/fullchain.pem nginx/ssl/cert.pem
cp /etc/letsencrypt/live/your-domain.com/privkey.pem nginx/ssl/key.pem

# Restart nginx
docker-compose restart nginx
```

---

## POS Integration

### Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Kamakunji Market                      │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │  POS 1   │  │  POS 2   │  │  POS 3   │  (Mobile)   │
│  │ (Tablet) │  │ (Tablet) │  │ (Phone)  │              │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘              │
│       │             │             │                      │
│       └─────────────┼─────────────┘                      │
│                     │                                    │
│              ┌──────▼──────┐                            │
│              │   WiFi LAN  │                            │
│              └──────┬──────┘                            │
│                     │                                    │
│       ┌─────────────┼─────────────┐                     │
│       │             │             │                     │
│  ┌────▼────┐  ┌────▼────┐  ┌─────▼─────┐               │
│  │ Backend │  │  Store  │  │ Database  │               │
│  │   API   │  │  Mgmt   │  │PostgreSQL │               │
│  └─────────┘  └─────────┘  └───────────┘               │
│                     (Local Server)                      │
└─────────────────────────────────────────────────────────┘
```

### Configure POS Terminals

1. **Network Setup**
   - Connect all POS devices to the same WiFi network
   - Ensure server has a static IP address (e.g., 192.168.1.100)

2. **Update Mobile App Configuration**

```dart
// mobile/lib/core/network/api_client.dart
static const String API_URL = 'http://192.168.1.100:3000/api/v1';
```

3. **Deploy Mobile App to Devices**

```bash
# Build APK for Android
flutter build apk --release

# Build IPA for iOS (requires Mac)
flutter build ipa

# Install via USB or QR code
```

4. **Test POS Integration**
   - Login with cashier credentials
   - Create a test sale
   - Verify stock updates in Store Management System
   - Check transaction history

---

## RBAC Configuration

### Role Permissions Matrix

| Permission | ADMIN | MANAGER | CASHIER | VIEWER |
|------------|-------|---------|---------|--------|
| Manage Users | ✅ | ❌ | ❌ | ❌ |
| Manage Products | ✅ | ✅ | ❌ | ❌ |
| Manage Transactions | ✅ | ✅ | ✅ | ❌ |
| View Reports | ✅ | ✅ | ✅ | ✅ |
| Stock Adjustments | ✅ | ✅ | ✅ | ❌ |
| Approve Adjustments | ✅ | ❌ | ❌ | ❌ |
| Access Settings | ✅ | ✅ | ✅ | ❌ |
| POS Access | ✅ | ✅ | ✅ | ❌ |

### Create User Roles

```bash
# Connect to database
psql -U store_user -d store_db

# View existing users
SELECT id, email, name, role FROM users;

# Update user role
UPDATE users SET role = 'CASHIER' WHERE email = 'cashier@kamakunji.com';

# Verify
SELECT * FROM users WHERE email = 'cashier@kamakunji.com';
```

### Assign POS Devices to Cashiers

```sql
-- In backend database
INSERT INTO devices (branch_id, device_uuid, name, model, os_version, app_version, is_active)
VALUES 
  ('branch-id-1', 'uuid-1', 'POS Terminal 1', 'Samsung Tab A8', 'Android 13', '1.0.0', true),
  ('branch-id-1', 'uuid-2', 'POS Terminal 2', 'Samsung Tab A8', 'Android 13', '1.0.0', true);
```

---

## Troubleshooting

### Database Connection Issues

```bash
# Check PostgreSQL is running
pg_isready

# Test connection
psql -U store_user -d store_db -h localhost

# Reset password
psql -U postgres
ALTER USER store_user WITH PASSWORD 'new_password';
```

### Build Errors

```bash
# Clear cache and rebuild
rm -rf node_modules .next
npm install
npm run build

# For mobile
flutter clean
flutter pub get
flutter build apk
```

### POS Not Connecting

1. Check network connectivity: `ping 192.168.1.100`
2. Verify API URL in mobile app
3. Check firewall rules allow port 3000
4. Review backend logs: `pm2 logs pos-backend`

### UI Overflow Issues

If you still experience pixel overflow:

```css
/* Add to globals.css */
* {
  box-sizing: border-box;
}

html, body {
  overflow-x: hidden;
  max-width: 100vw;
}
```

---

## Monitoring & Maintenance

### Daily Checks

- [ ] Review transaction logs
- [ ] Check low stock alerts
- [ ] Verify backup completed
- [ ] Monitor disk space

### Weekly Tasks

- [ ] Review pending stock adjustments
- [ ] Update product prices if needed
- [ ] Check for system updates
- [ ] Review user access logs

### Monthly Maintenance

- [ ] Database backup verification
- [ ] Security updates
- [ ] Performance optimization
- [ ] User access review

---

## Support

For issues or questions:
- Check logs: `docker-compose logs -f`
- Review error reports in Store Management System
- Contact system administrator

**Emergency Contacts:**
- System Admin: [Your Contact]
- Database Admin: [DBA Contact]
- Network Support: [Network Contact]
