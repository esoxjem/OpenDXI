---
title: "CSS/Tailwind Styles Not Loading After API-Only to Full-Stack Rails Migration"
category: "security-issues"
tags:
  - content-security-policy
  - tailwind-css
  - rails
  - hotwire
  - asset-pipeline
  - migration
  - csp
  - propshaft
module_affected: "Rails View Layer / Asset Pipeline"
symptoms:
  - "CSS file served with HTTP 200 status and correct MIME type (text/css)"
  - "HTML references correct fingerprinted stylesheet URL (/assets/tailwind-*.css)"
  - "Browser displays completely unstyled HTML with browser default styles only"
  - "Issue persists in both automated and regular browsers"
  - "No console errors indicating missing files or 404s"
root_cause: "Content Security Policy (CSP) configured for API-only mode with 'default_src :none' blocks all resources including stylesheets from loading"
solution_summary: "Updated CSP configuration to allow stylesheets from same origin with 'style_src :self'"
date_documented: "2026-01-29"
---

# CSS/Tailwind Styles Not Loading After API-Only to Full-Stack Rails Migration

## Problem

After migrating from a Next.js frontend + API-only Rails backend to a full-stack Rails application with Hotwire (Turbo + Stimulus), CSS styles were not being applied despite the CSS file being served correctly.

### Observable Symptoms

1. CSS file served correctly (HTTP 200, 23KB, `Content-Type: text/css`)
2. HTML contained correct fingerprinted stylesheet URL (`/assets/tailwind-01ab5eb3.css`)
3. Browser displayed completely unstyled HTML (browser defaults)
4. Issue occurred in ALL browsers (Chrome, Safari, automated testing tools)
5. No 404 errors, no network failures visible in DevTools

## Investigation Steps

### 1. Verified Tailwind CSS Build Process

Checked that the CSS watcher process was running via `bin/dev`:

```bash
tail -30 /tmp/rails-server.log | grep -E "(web|css)"
# Output showed both web.1 and css.1 processes running
```

### 2. Confirmed CSS File Exists and Has Content

```bash
ls -la api/app/assets/builds/tailwind.css
# -rw-r--r-- 23016 bytes - valid file exists

curl -s "http://localhost:3000/assets/tailwind-01ab5eb3.css" | head -20
# /*! tailwindcss v4.1.18 | MIT License | https://tailwindcss.com */
# ... valid CSS content
```

### 3. Verified HTTP Response

```bash
curl -sI "http://localhost:3000/assets/tailwind-01ab5eb3.css"
# HTTP/1.1 200 OK
# content-type: text/css
# cache-control: public, max-age=31536000, immutable
```

### 4. Checked HTML Source

```bash
curl -s http://localhost:3000/ | grep stylesheet
# <link rel="stylesheet" href="/assets/tailwind-01ab5eb3.css" data-turbo-track="reload" />
```

Everything looked correct - but CSS still wasn't applied!

### 5. Ran Parallel Review Agents

Used specialized review agents to analyze the codebase. Both `kieran-rails-reviewer` and asset pipeline analyzer identified the same root cause: **Content Security Policy**.

## Root Cause

**File:** `api/config/initializers/content_security_policy.rb`

The CSP configuration was still set for "API-only mode" from when the Rails app only served JSON:

```ruby
# Old configuration (BLOCKING ALL RESOURCES)
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :none  # <-- THIS WAS THE PROBLEM
    policy.frame_ancestors :none
  end
end
```

The comment in the file explained the original intent:
> "Since this is a JSON API with no HTML responses, CSP is minimal. The frontend (Next.js) handles its own CSP."

### Why This Breaks CSS

`default_src :none` tells the browser to **block ALL resources** unless explicitly allowed. Since there was no `style_src` directive, stylesheets were blocked by default.

The browser:
1. Received the CSS file (HTTP 200) ✅
2. Checked CSP header: `default-src 'none'`
3. No `style-src` directive found
4. Fell back to `default-src 'none'`
5. **Blocked the stylesheet from being applied** ❌

This is why the CSS appeared to load (network success) but wasn't applied (CSP blocked execution).

## Solution

Updated CSP for full-stack Rails with Hotwire:

```ruby
# frozen_string_literal: true

# Content Security Policy configuration for full-stack Rails with Hotwire
#
# See: https://guides.rubyonrails.org/security.html#content-security-policy-header
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :data, "https:"
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self
    policy.frame_ancestors :none

    # Allow WebSocket connections for Turbo in development
    if Rails.env.development?
      policy.connect_src :self, "ws://localhost:*"
    else
      policy.connect_src :self
    end
  end
end
```

### What Each Directive Does

| Directive | Value | Purpose |
|-----------|-------|---------|
| `default_src` | `:self` | Allow resources from same origin by default |
| `style_src` | `:self` | Allow stylesheets from same origin (Tailwind CSS) |
| `script_src` | `:self` | Allow scripts from same origin (Turbo, Stimulus) |
| `font_src` | `:self, :data` | Allow fonts from same origin and data URIs |
| `img_src` | `:self, :data, "https:"` | Allow images from origin, data URIs, and HTTPS sources |
| `connect_src` | `:self, "ws://localhost:*"` | Allow WebSockets for Turbo (dev only) |
| `object_src` | `:none` | Block plugins/embeds (security) |
| `frame_ancestors` | `:none` | Prevent clickjacking |

## Prevention Checklist

When migrating from API-only to full-stack Rails:

### Before Migration

- [ ] Document current CSP configuration
- [ ] Identify all resource types the new views will need (CSS, JS, fonts, images)
- [ ] Plan CSP updates as part of migration tasks

### During Migration

- [ ] Update CSP initializer when adding view layer
- [ ] Add `style_src :self` for stylesheets
- [ ] Add `script_src :self` for JavaScript
- [ ] Add `connect_src` with WebSocket support for Hotwire/Turbo
- [ ] Test in browser with DevTools Console open

### Quick Diagnostic

If CSS doesn't load after migration:

1. Open browser DevTools Console
2. Look for CSP violation errors (red text mentioning "Content Security Policy")
3. Check Network tab > Response Headers for `Content-Security-Policy`
4. Verify CSP includes `style-src 'self'`

## Related Documentation

- [Rails Security Guide: CSP](https://guides.rubyonrails.org/security.html#content-security-policy-header)
- [Migration Plan: Next.js to Rails](/docs/plans/2026-01-28-feat-nextjs-to-rails-frontend-migration-plan.md)
- [Deployment Fixes: Asset Pipeline](/docs/solutions/deployment-issues/coolify-docker-deployment-fixes.md)

## Key Takeaway

**Always update CSP when changing application architecture.** API-only apps need minimal CSP, but full-stack apps serving HTML need explicit permissions for all resource types (styles, scripts, fonts, images, WebSockets).
