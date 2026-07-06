SELECT b.id, b.name, b.code, p.name as pos_client 
FROM branches b 
LEFT JOIN pos_clients p ON b."posClientId" = p.id 
WHERE p.slug = 'levisa' 
LIMIT 10;
