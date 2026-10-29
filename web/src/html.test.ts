import { describe, expect, it } from "vitest";
import { escapeHtml } from "./html";

describe("escapeHtml", () => {
  it("neutralises markup and attribute breakouts", () => {
    expect(escapeHtml(`<img src=x onerror="alert('x')">&`)).toBe("&#60;img src=x onerror=&#34;alert(&#39;x&#39;)&#34;&#62;&#38;");
  });
  it("leaves module names untouched", () => {
    expect(escapeHtml("Domain_UI2")).toBe("Domain_UI2");
  });
});
