-- Create a test tenant for Levisa
INSERT INTO tenants (id, name, slug, "isActive", "createdAt", "updatedAt", settings)
VALUES (gen_random_uuid(), 'Levisa Adventures', 'levisa-adventures', true, NOW(), NOW(), '{}');

-- Get Levisa pos_client ID
SELECT id FROM pos_clients WHERE slug = 'levisa';

-- Get tenant ID
SELECT id FROM tenants WHERE slug = 'levisa-adventures';

-- Insert Levisa test branch
INSERT INTO branches (id, "tenantId", "posClientId", name, code, timezone, "isActive", "createdAt", "updatedAt", settings)
SELECT 
  gen_random_uuid(),
  (SELECT id FROM tenants WHERE slug = 'levisa-adventures'),
  (SELECT id FROM pos_clients WHERE slug = 'levisa'),
  'Levisa Main Nairobi',
  'LEVISANBI',
  'Africa/Nairobi',
  true,
  NOW(),
  NOW(),
  '{}';

-- Show results
SELECT b.id, b.name, b.code, p.name as pos_client 
FROM branches b 
LEFT JOIN pos_clients p ON b."posClientId" = p.id 
WHERE p.slug = 'levisa';
