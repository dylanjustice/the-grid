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
    deleteOp.locator("td.response-col_status:not(.col_header)"),
  ).toHaveText("200");

  // GET /get
  const getOp = page.locator('[id="operations-HTTP Methods-get_get"]');
  await getOp.click();
  await getOp.locator("button", { hasText: "Try it out" }).click();
  await getOp.locator("button", { hasText: "Execute" }).click();
  await expect(
    getOp.locator("td.response-col_status:not(.col_header)"),
  ).toHaveText("200");

  // PATCH /patch
  const patchOp = page.locator('[id="operations-HTTP Methods-patch_patch"]');
  await patchOp.click();
  await patchOp.locator("button", { hasText: "Try it out" }).click();
  await patchOp.locator("button", { hasText: "Execute" }).click();
  await expect(
    patchOp.locator("td.response-col_status:not(.col_header)"),
  ).toHaveText("200");

  // POST /post
  const postOp = page.locator('[id="operations-HTTP Methods-post_post"]');
  await postOp.click();
  await postOp.locator("button", { hasText: "Try it out" }).click();
  await postOp.locator("button", { hasText: "Execute" }).click();
  await expect(
    postOp.locator("td.response-col_status:not(.col_header)"),
  ).toHaveText("200");

  // PUT /put
  const putOp = page.locator('[id="operations-HTTP Methods-put_put"]');
  await putOp.click();
  await putOp.locator("button", { hasText: "Try it out" }).click();
  await putOp.locator("button", { hasText: "Execute" }).click();
  await expect(
    putOp.locator("td.response-col_status:not(.col_header)"),
  ).toHaveText("200");
});
