import { test, expect } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  await page.goto("https://httpbin.org", { waitUntil: "networkidle" });
});

test("HTTP Methods", async ({ page }) => {
  await page.locator("#operations-tag-HTTP_Methods").click();

  await test.step("DELETE", async () => {
    const op = page.locator('[id="operations-HTTP Methods-delete_delete"]');
    await op.waitFor();
    await op.click();
    await op.locator("button", { hasText: "Try it out" }).click();
    await op.locator("button", { hasText: "Execute" }).click();
    await expect(
      op.locator("td.response-col_status:not(.col_header)").first(),
    ).toHaveText("200");
  });

  await test.step("GET", async () => {
    const op = page.locator('[id="operations-HTTP Methods-get_get"]');
    await op.click();
    await op.locator("button", { hasText: "Try it out" }).click();
    await op.locator("button", { hasText: "Execute" }).click();
    await expect(
      op.locator("td.response-col_status:not(.col_header)").first(),
    ).toHaveText("200");
  });

  await test.step("PATCH", async () => {
    const op = page.locator('[id="operations-HTTP Methods-patch_patch"]');
    await op.click();
    await op.locator("button", { hasText: "Try it out" }).click();
    await op.locator("button", { hasText: "Execute" }).click();
    await expect(
      op.locator("td.response-col_status:not(.col_header)").first(),
    ).toHaveText("200");
  });

  await test.step("POST", async () => {
    const op = page.locator('[id="operations-HTTP Methods-post_post"]');
    await op.click();
    await op.locator("button", { hasText: "Try it out" }).click();
    await op.locator("button", { hasText: "Execute" }).click();
    await expect(
      op.locator("td.response-col_status:not(.col_header)").first(),
    ).toHaveText("200");
  });

  await test.step("PUT", async () => {
    const op = page.locator('[id="operations-HTTP Methods-put_put"]');
    await op.click();
    await op.locator("button", { hasText: "Try it out" }).click();
    await op.locator("button", { hasText: "Execute" }).click();
    await expect(
      op.locator("td.response-col_status:not(.col_header)").first(),
    ).toHaveText("200");
  });
});
