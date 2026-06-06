-- Seed data for pos_clients table
INSERT INTO pos_clients (id, name, slug, logo, "isActive", settings, "createdAt", "updatedAt")
VALUES
  (gen_random_uuid(), 'Levisa', 'levisa', 'https://example.com/levisa-logo.png', true, '{}', NOW(), NOW()),
  (gen_random_uuid(), 'TSL', 'tsl', 'https://example.com/tsl-logo.png', true, '{}', NOW(), NOW()),
  (gen_random_uuid(), 'Kate', 'kate', 'https://example.com/kate-logo.png', true, '{}', NOW(), NOW())
ON CONFLICT (slug) DO NOTHING;

-- Display results
SELECT id, name, slug, "isActive", "createdAt" FROM pos_clients;
