/**
 * TanStack Query hook for authentication state.
 *
 * Uses the existing TanStack Query infrastructure to manage auth state.
 * No separate AuthProvider needed - just use this hook anywhere.
 */

"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { checkAuthStatus, logout as apiLogout, AuthUser } from "@/lib/api";

export type AuthState =
  | "checking"
  | "server_unreachable"
  | "authenticated"
  | "sign_in_required";

interface UseAuthResult {
  user: AuthUser | null;
  isLoading: boolean;
  isAuthenticated: boolean;
  authState: AuthState;
  statusMessage: string;
  error: string | null;
  logout: () => Promise<void>;
}

/**
 * Hook to check and manage authentication state.
 *
 * Uses 5-minute stale time to reduce API calls while keeping auth
 * state reasonably fresh. The query is not retried on failure since
 * a failed auth check usually means the user isn't logged in.
 */
export function useAuth(): UseAuthResult {
  const queryClient = useQueryClient();

  const { data, isLoading, error } = useQuery({
    queryKey: ["auth"],
    queryFn: checkAuthStatus,
    retry: false,
    refetchInterval: (query) => query.state.error ? 2000 : false,
    staleTime: 5 * 60 * 1000, // 5 minutes - data considered fresh
    gcTime: 30 * 60 * 1000,   // 30 minutes - keep in cache longer
  });

  const authState: AuthState = data?.authenticated
    ? "authenticated"
    : data
      ? "sign_in_required"
      : error
        ? "server_unreachable"
        : "checking";

  const statusMessage = {
    checking: "Checking GitHub sign-in status...",
    server_unreachable: "Waiting for the local server...",
    authenticated: "Signed in.",
    sign_in_required: "GitHub sign-in required.",
  }[authState];

  const logout = async () => {
    try {
      await apiLogout();
    } catch (error) {
      // Log error but still proceed with client-side logout
      console.error("Logout API failed:", error);
    }
    // Always clear client state and redirect
    queryClient.setQueryData(["auth"], { authenticated: false });
    window.location.href = "/login";
  };

  return {
    user: data?.user ?? null,
    isLoading: isLoading || authState === "server_unreachable",
    isAuthenticated: data?.authenticated ?? false,
    authState,
    statusMessage,
    error: error instanceof Error ? error.message : null,
    logout,
  };
}
