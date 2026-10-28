import { test, expect } from "@playwright/test";

test("intentional failure - screenshot capture check", async ({ page }) => {
  await page.goto("http://localhost:8080");
  await expect(page.locator("h1")).toHaveText("this text will never match");
});
