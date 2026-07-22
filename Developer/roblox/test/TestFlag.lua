-- TestFlag — present only in test builds, never in production.
--
-- This module exists so the test bootstrap (test/bootstrap.server.lua) can
-- verify it is running inside a TEST place (built from test.project.json)
-- and NOT a production place (built from default.project.json).
--
-- Mapped in test.project.json → ReplicatedStorage.TestFlag
-- Intentionally absent from default.project.json.
-- If a production place ever loads this flag, the build mapping is wrong.
return true
