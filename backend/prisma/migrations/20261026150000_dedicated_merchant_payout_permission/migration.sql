-- Separate control of a shop's settlement destination from staff role editing.
-- Existing roles and personal overrides inherit the old effective capability
-- once, so current payout administrators keep access after the guard changes.
INSERT INTO "permissions" ("id", "key", "feature", "action", "label", "createdAt")
VALUES (
    gen_random_uuid()::text,
    'payments.manage_payout',
    'payments',
    'manage_payout',
    'Manage the business payout account',
    CURRENT_TIMESTAMP
)
ON CONFLICT ("key") DO UPDATE SET
    "feature" = EXCLUDED."feature",
    "action" = EXCLUDED."action",
    "label" = EXCLUDED."label";

INSERT INTO "role_permissions" ("id", "roleId", "permissionKey", "createdAt")
SELECT gen_random_uuid()::text, existing."roleId", 'payments.manage_payout', existing."createdAt"
FROM "role_permissions" AS existing
WHERE existing."permissionKey" = 'roles.update'
ON CONFLICT ("roleId", "permissionKey") DO NOTHING;

INSERT INTO "user_permission_overrides" (
    "id", "userId", "permissionKey", "grant", "reason", "createdById", "createdAt", "updatedAt"
)
SELECT
    gen_random_uuid()::text,
    existing."userId",
    'payments.manage_payout',
    existing."grant",
    existing."reason",
    existing."createdById",
    existing."createdAt",
    existing."updatedAt"
FROM "user_permission_overrides" AS existing
WHERE existing."permissionKey" = 'roles.update'
ON CONFLICT ("userId", "permissionKey") DO NOTHING;
