import type { NextConfig } from "next";

// Get API URL for CSP - must be known at build time
const apiUrl = process.env.NEXT_PUBLIC_API_URL || "http://localhost:3000";
const apiOrigin = new URL(apiUrl).origin;

const nextConfig: NextConfig = {
  output: "standalone",
  poweredByHeader: false, // Security: Remove X-Powered-By header

  // Security headers
  async headers() {
    // Build CSP with API origin for connect-src
    const cspDirectives = [
      "default-src 'self'",
      "script-src 'self' 'unsafe-inline' 'unsafe-eval'",
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data: https:",
      `connect-src 'self' ${apiOrigin}`,
      "frame-ancestors 'self'",
    ].join("; ");

    return [
      {
        source: "/:path*",
        headers: [
          { key: "Strict-Transport-Security", value: "max-age=31536000; includeSubDomains" },
          { key: "X-Frame-Options", value: "DENY" },
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
          { key: "Content-Security-Policy-Report-Only", value: cspDirectives },
        ],
      },
    ];
  },
};

export default nextConfig;
