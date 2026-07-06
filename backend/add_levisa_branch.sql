-- Get Levisa pos_client ID
SELECT id INTO TEMP levisa_id FROM pos_clients WHERE slug = 'levisa';

-- Insert Levisa test branches
INSERT INTO branches (id, "tenantId", "posClientId", name, code, timezone, "isActive", "createdAt", "updatedAt", settings)
SELECT 
  gen_random_uuid(),
  t.id,
  l.id,
  'Levisa Main Nairobi',
  'LEVISANBI',
  'Africa/Nairobi',
  true,
  NOW(),
  NOW(),
  '{}'
FROM tenants t, levisa_id l
LIMIT 1;

-- Show results
SELECT b.id, b.name, b.code, p.name as pos_client 
FROM branches b 
LEFT JOIN pos_clients p ON b."posClientId" = p.id 
WHERE p.slug = 'levisa';

-- Cleanup
DROP TABLE IF EXISTS levisa_id;
