# Hybrid Multi-Branch POS System

A comprehensive Point of Sale system supporting multiple branches with seamless online/offline operation.

## Features

- **Offline-First Design**: Sales continue without internet connectivity
- **Multi-Branch Support**: Tenant → Branches → Devices → Users hierarchy
- **Multiple Payment Methods**: M-Pesa (Daraja), PesaPal, TouristTap (NFC)
- **Smart Product Selection**: Categories, search, favorites, and recent items
- **Real-time Sync**: Automatic background sync when online
- **Role-Based Access**: Cashier, Supervisor, Manager, Admin roles
- **Inventory Management**: Branch-level stock tracking with inter-branch transfers

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           MOBILE POS APP (Flutter)                       │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │
│  │ Products │ │  Sales   │ │ Payments │ │ Inventory│ │  Sync Engine │  │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └──────┬───────┘  │
│       │            │            │            │              │           │
│  ┌────┴────────────┴────────────┴────────────┴──────────────┴───────┐  │
│  │                    LOCAL SQLite DATABASE                          │  │
│  │              (Products, Prices, Customers, Receipts)              │  │
│  └───────────────────────────────┬───────────────────────────────────┘  │
└──────────────────────────────────┼──────────────────────────────────────┘
                                   │ Event Queue (Offline Transactions)
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           API GATEWAY (NestJS)                           │
│         Authentication │ Rate Limiting │ Request Validation             │
└─────────────────────────────────┬───────────────────────────────────────┘
                                  │
        ┌─────────┬───────────────┼───────────────┬─────────────┐
        ▼         ▼               ▼               ▼             ▼
┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐
│   Auth    │ │  Branch   │ │  Catalog  │ │   Sales   │ │ Inventory │
│  Service  │ │  Service  │ │  Service  │ │  Service  │ │  Service  │
└─────┬─────┘ └─────┬─────┘ └─────┬─────┘ └─────┬─────┘ └─────┬─────┘
      │             │             │             │             │
      └─────────────┴─────────────┴──────┬──────┴─────────────┘
                                         ▼
                              ┌─────────────────────┐
                              │     PostgreSQL      │
                              │     + Redis Cache   │
                              └─────────────────────┘
```

## Technology Stack

| Component | Technology |
|-----------|------------|
| Mobile App | Flutter (Dart) |
| Backend | NestJS (TypeScript) |
| Database | PostgreSQL |
| Cache & Queue | Redis |
| Mobile DB | SQLite (Drift) |
| Auth | JWT + Refresh Tokens |

## Project Structure

```
pos-system/
├── backend/                 # NestJS Backend API
│   ├── src/
│   │   ├── auth/           # Authentication & authorization
│   │   ├── branches/       # Branch & device management
│   │   ├── catalog/        # Products & pricing
│   │   ├── sales/          # Sales & receipts
│   │   ├── inventory/      # Stock management
│   │   ├── payments/       # Payment integrations
│   │   ├── sync/           # Offline sync handling
│   │   ├── reporting/      # Analytics & reports
│   │   └── common/         # Shared utilities
│   └── prisma/             # Database schema
├── mobile/                  # Flutter Mobile App
│   ├── lib/
│   │   ├── core/           # Core utilities
│   │   ├── data/           # Data layer (SQLite, API)
│   │   ├── domain/         # Business logic
│   │   └── presentation/   # UI screens
│   └── assets/             # Images, fonts
└── docs/                    # Documentation
```

## Getting Started

### Backend Setup

```bash
cd backend
npm install
cp .env.example .env
# Configure your database and API keys
npx prisma migrate dev
npm run start:dev
```

### Mobile App Setup

```bash
cd mobile
flutter pub get
flutter run
```

## Environment Variables

See `.env.example` files in each project for required configuration.

## API Documentation

API documentation is available at `/api/docs` when running the backend server.

## License

MIT License
