/**
 * Client-side providers for the application.
 *
 * Wraps the app with TanStack Query provider for data fetching.
 */

"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";

export function Providers({ children }: { children: ReactNode }) {
  // Create QueryClient inside component to avoid sharing state between requests
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            // Don't refetch on window focus in development
            refetchOnWindowFocus: process.env.NODE_ENV === "production",
            // Smart retry: don't retry on auth errors
            retry: (failureCount, error) => {
              // Don't retry on auth errors - user needs to log in
              if (error instanceof Error && error.message === "Unauthorized") {
                return false;
              }
              // Retry other errors once
              return failureCount < 1;
            },
          },
        },
      })
  );

  return (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  );
}
