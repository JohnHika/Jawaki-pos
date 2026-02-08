# POS System Makefile
# Common commands for development and deployment

.PHONY: help install dev build test clean docker-up docker-down migrate

# Default target
help:
	@echo "POS System - Available Commands"
	@echo "================================"
	@echo "  make install      - Install dependencies for backend and mobile"
	@echo "  make dev          - Start development environment"
	@echo "  make build        - Build for production"
	@echo "  make test         - Run tests"
	@echo "  make clean        - Clean build artifacts"
	@echo "  make docker-up    - Start Docker containers"
	@echo "  make docker-down  - Stop Docker containers"
	@echo "  make docker-dev   - Start Docker with dev profile"
	@echo "  make migrate      - Run database migrations"
	@echo "  make seed         - Seed database with sample data"
	@echo "  make logs         - View Docker logs"

# Install dependencies
install:
	@echo "Installing backend dependencies..."
	cd backend && npm install
	@echo "Installing Flutter dependencies..."
	cd mobile && flutter pub get
	@echo "Dependencies installed successfully!"

# Development
dev:
	@echo "Starting development environment..."
	cd backend && npm run start:dev

# Build for production
build:
	@echo "Building backend..."
	cd backend && npm run build
	@echo "Building mobile app..."
	cd mobile && flutter build apk --release
	@echo "Build complete!"

# Run tests
test:
	@echo "Running backend tests..."
	cd backend && npm run test
	@echo "Running mobile tests..."
	cd mobile && flutter test

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	cd backend && rm -rf dist node_modules
	cd mobile && flutter clean
	@echo "Clean complete!"

# Docker commands
docker-up:
	docker-compose up -d

docker-down:
	docker-compose down

docker-dev:
	docker-compose --profile dev up -d

docker-build:
	docker-compose build --no-cache

docker-logs:
	docker-compose logs -f

logs:
	docker-compose logs -f backend

# Database
migrate:
	cd backend && npx prisma migrate deploy

migrate-dev:
	cd backend && npx prisma migrate dev

seed:
	cd backend && npx prisma db seed

studio:
	cd backend && npx prisma studio

# Generate Prisma client
generate:
	cd backend && npx prisma generate

# SSL certificates (for development)
ssl-dev:
	@mkdir -p nginx/ssl
	openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
		-keyout nginx/ssl/privkey.pem \
		-out nginx/ssl/fullchain.pem \
		-subj "/CN=localhost"
	@echo "Development SSL certificates generated!"
