import { test, expect } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  await page.goto("https://httpbin.org", { waitUntil: "networkidle" });
});

test("HTTP Methods", async ({ page }) => {
  // Expand the HTTP Methods section
  await page.locator("#operations-tag-HTTP_Methods").click();

  // Wait for operations to render
  const deleteOp = page.locator('[id="operations-HTTP Methods-delete_delete"]');
  await deleteOp.waitFor();

  // DELETE /delete
  await deleteOp.click();
  await deleteOp.locator("button", { hasText: "Try it out" }).click();
  await deleteOp.locator("button", { hasText: "Execute" }).click();
  await expect(
    deleteOp.locator("td.response-col_status:not(.col_header)")
  ).toHaveText("200");

  // GET /get
  const getOp = page.locator('[id="operations-HTTP Methods-get_get"]');
  await getOp.click();
  await getOp.locator("button", { hasText: "Try it out" }).click();
  await getOp.locator("button", { hasText: "Execute" }).click();
  await expect(
    getOp.locator("td.response-col_status:not(.col_header)")
  ).toHaveText("200");
});
