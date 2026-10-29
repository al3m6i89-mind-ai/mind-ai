-- A region belongs to the infrastructure that serves it; NULL keeps it open to every provider.
ALTER TABLE regions ADD COLUMN provider_id VARCHAR(40);
