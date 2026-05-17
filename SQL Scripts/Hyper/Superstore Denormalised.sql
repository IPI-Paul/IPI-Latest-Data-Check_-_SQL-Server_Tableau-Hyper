SELECT 
    DATE_TRUNC('month', MAX("Order Date")) + INTERVAL '1 month' - INTERVAL '1 day' AS Latest
FROM "Extract"."Extract"    