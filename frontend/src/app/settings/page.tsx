/**
 * Settings page for user management.
 *
 * Only accessible to users with owner role.
 * Displays list of all users with role dropdowns for assignment.
 */

"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/hooks/useAuth";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

const API_BASE = process.env.NEXT_PUBLIC_API_URL || "http://localhost:3000";

interface User {
  id: number;
  github_id: number;
  login: string;
  name: string | null;
  avatar_url: string;
  role: "owner" | "developer";
}

interface UsersResponse {
  users: User[];
}

export default function SettingsPage() {
  const { user, isLoading: authLoading } = useAuth();
  const router = useRouter();
  const queryClient = useQueryClient();

  // Redirect non-owners after auth loads
  useEffect(() => {
    if (!authLoading && user?.role !== "owner") {
      router.replace("/");
    }
  }, [authLoading, user, router]);

  // Fetch users (only when user is owner)
  const { data, isLoading, error } = useQuery({
    queryKey: ["users"],
    queryFn: async () => {
      const res = await fetch(`${API_BASE}/api/users`, {
        credentials: "include",
      });
      if (!res.ok) {
        if (res.status === 403) {
          throw new Error("Access denied");
        }
        throw new Error("Failed to fetch users");
      }
      return res.json() as Promise<UsersResponse>;
    },
    enabled: user?.role === "owner",
  });

  // Update role mutation with optimistic updates
  const updateRole = useMutation({
    mutationFn: async ({ id, role }: { id: number; role: string }) => {
      const res = await fetch(`${API_BASE}/api/users/${id}`, {
        method: "PATCH",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ role }),
      });
      if (!res.ok) throw new Error("Failed to update role");
      return res.json();
    },
    // Optimistic update
    onMutate: async ({ id, role }) => {
      await queryClient.cancelQueries({ queryKey: ["users"] });
      const previousUsers = queryClient.getQueryData<UsersResponse>(["users"]);

      queryClient.setQueryData<UsersResponse>(["users"], (old) => {
        if (!old) return old;
        return {
          users: old.users.map((u) =>
            u.id === id ? { ...u, role: role as "owner" | "developer" } : u
          ),
        };
      });

      return { previousUsers };
    },
    onError: (_err, _vars, context) => {
      // Rollback on error
      if (context?.previousUsers) {
        queryClient.setQueryData(["users"], context.previousUsers);
      }
    },
    onSettled: () => {
      // Refetch to ensure consistency
      queryClient.invalidateQueries({ queryKey: ["users"] });
    },
  });

  // Show loading while checking auth
  if (authLoading) {
    return (
      <div className="container mx-auto py-8 px-4">
        <p className="text-muted-foreground">Loading...</p>
      </div>
    );
  }

  // Don't render anything for non-owners (redirect will happen)
  if (user?.role !== "owner") {
    return null;
  }

  return (
    <div className="container mx-auto py-8 px-4 max-w-3xl">
      <h1 className="text-2xl font-bold mb-6">Settings</h1>

      <section>
        <h2 className="text-lg font-semibold mb-4">Users</h2>

        {isLoading ? (
          <p className="text-muted-foreground">Loading users...</p>
        ) : error ? (
          <p className="text-destructive">
            Failed to load users. Please try again.
          </p>
        ) : (
          <div className="border rounded-lg divide-y">
            {data?.users.map((u) => (
              <div
                key={u.id}
                className="flex items-center justify-between p-4"
              >
                <div className="flex items-center gap-3">
                  <Avatar className="h-8 w-8">
                    <AvatarImage src={u.avatar_url} alt={u.login} />
                    <AvatarFallback>
                      {u.login[0]?.toUpperCase() || "?"}
                    </AvatarFallback>
                  </Avatar>
                  <div>
                    <p className="font-medium">{u.login}</p>
                    {u.name && (
                      <p className="text-sm text-muted-foreground">{u.name}</p>
                    )}
                  </div>
                </div>
                <Select
                  value={u.role}
                  onValueChange={(role) => updateRole.mutate({ id: u.id, role })}
                  disabled={updateRole.isPending}
                >
                  <SelectTrigger className="w-32">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="developer">Developer</SelectItem>
                    <SelectItem value="owner">Owner</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            ))}
            {data?.users.length === 0 && (
              <div className="p-4 text-muted-foreground text-center">
                No users found.
              </div>
            )}
          </div>
        )}
      </section>
    </div>
  );
}
