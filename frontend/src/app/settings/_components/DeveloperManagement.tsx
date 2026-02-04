/**
 * Developer visibility management section for the Settings page.
 *
 * Handles:
 *   - Listing managed developers with visibility toggle
 *   - Syncing developers from GitHub
 *   - Showing sync results
 *
 * Owns its own TanStack Query state for developers and sync mutations.
 */

"use client";

import { useQueryClient, useQuery, useMutation } from "@tanstack/react-query";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { Loader2, RefreshCw } from "lucide-react";

const API_BASE = process.env.NEXT_PUBLIC_API_URL || "http://localhost:3000";

interface ManagedDeveloper {
  id: number;
  github_id: number;
  github_login: string;
  name: string | null;
  avatar_url: string;
  visible: boolean;
  source: "org_member" | "external";
  teams: { id: number; name: string; slug: string }[];
}

interface ManagedDevelopersResponse {
  developers: ManagedDeveloper[];
}

interface SyncResult {
  success: boolean;
  members_synced: number;
  teams_synced: number;
  external_detected: number;
}

export function DeveloperManagement() {
  const queryClient = useQueryClient();

  // Fetch managed developers
  const {
    data: devsData,
    isLoading: devsLoading,
    error: devsError,
  } = useQuery({
    queryKey: ["managed-developers"],
    queryFn: async () => {
      const res = await fetch(`${API_BASE}/api/developers/managed`, {
        credentials: "include",
      });
      if (!res.ok) throw new Error("Failed to fetch developers");
      return res.json() as Promise<ManagedDevelopersResponse>;
    },
  });

  // Sync developers from GitHub
  const syncDevelopers = useMutation({
    mutationFn: async () => {
      const res = await fetch(`${API_BASE}/api/developers/sync`, {
        method: "POST",
        credentials: "include",
      });
      if (!res.ok) throw new Error("Failed to sync from GitHub");
      return res.json() as Promise<SyncResult>;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["managed-developers"] });
      queryClient.invalidateQueries({ queryKey: ["teams"] });
    },
  });

  // Toggle developer visibility with optimistic update
  const toggleVisibility = useMutation({
    mutationFn: async ({ id, visible }: { id: number; visible: boolean }) => {
      const res = await fetch(`${API_BASE}/api/developers/${id}`, {
        method: "PATCH",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ developer: { visible } }),
      });
      if (!res.ok) throw new Error("Failed to update visibility");
      return res.json();
    },
    onMutate: async ({ id, visible }) => {
      await queryClient.cancelQueries({ queryKey: ["managed-developers"] });
      const previous =
        queryClient.getQueryData<ManagedDevelopersResponse>([
          "managed-developers",
        ]);

      queryClient.setQueryData<ManagedDevelopersResponse>(
        ["managed-developers"],
        (old) => {
          if (!old) return old;
          return {
            developers: old.developers.map((d) =>
              d.id === id ? { ...d, visible } : d
            ),
          };
        }
      );

      return { previous };
    },
    onError: (_err, _vars, context) => {
      if (context?.previous) {
        queryClient.setQueryData(["managed-developers"], context.previous);
      }
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ["managed-developers"] });
    },
  });

  const visibleCount =
    devsData?.developers.filter((d) => d.visible).length ?? 0;
  const totalCount = devsData?.developers.length ?? 0;

  return (
    <section className="mt-8">
      <div className="flex items-center justify-between mb-4">
        <div>
          <h2 className="text-lg font-semibold">Developers</h2>
          {totalCount > 0 && (
            <p className="text-sm text-muted-foreground">
              Showing {visibleCount} of {totalCount} developers on dashboard
            </p>
          )}
        </div>
        <Button
          size="sm"
          variant="outline"
          onClick={() => syncDevelopers.mutate()}
          disabled={syncDevelopers.isPending}
        >
          {syncDevelopers.isPending ? (
            <Loader2 className="h-4 w-4 mr-2 animate-spin" />
          ) : (
            <RefreshCw className="h-4 w-4 mr-2" />
          )}
          Sync from GitHub
        </Button>
      </div>

      {syncDevelopers.isSuccess && (
        <div className="mb-4 p-3 bg-muted rounded-lg text-sm">
          Synced {syncDevelopers.data.members_synced} members,{" "}
          {syncDevelopers.data.teams_synced} teams
          {syncDevelopers.data.external_detected > 0 && (
            <>
              , detected {syncDevelopers.data.external_detected} external
              contributors
            </>
          )}
        </div>
      )}

      {devsLoading ? (
        <p className="text-muted-foreground">Loading developers...</p>
      ) : devsError ? (
        <p className="text-destructive">
          Failed to load developers. Please try again.
        </p>
      ) : totalCount === 0 ? (
        <div className="border rounded-lg p-8 text-center text-muted-foreground">
          <p className="mb-2">No developers synced yet.</p>
          <p className="text-sm">
            Click &ldquo;Sync from GitHub&rdquo; to import your
            organization&apos;s members.
          </p>
        </div>
      ) : (
        <div className="border rounded-lg divide-y">
          {devsData?.developers.map((dev) => (
            <div
              key={dev.id}
              className="flex items-center justify-between p-4"
            >
              <div className="flex items-center gap-3">
                <Avatar className="h-8 w-8">
                  <AvatarImage
                    src={dev.avatar_url}
                    alt={dev.github_login}
                  />
                  <AvatarFallback>
                    {dev.github_login[0]?.toUpperCase() || "?"}
                  </AvatarFallback>
                </Avatar>
                <div>
                  <div className="flex items-center gap-2">
                    <p className="font-medium">{dev.github_login}</p>
                    <Badge
                      variant={
                        dev.source === "org_member" ? "secondary" : "outline"
                      }
                      className="text-[10px] px-1.5 py-0"
                    >
                      {dev.source === "org_member" ? "Org" : "External"}
                    </Badge>
                  </div>
                  {dev.name && (
                    <p className="text-sm text-muted-foreground">{dev.name}</p>
                  )}
                  {dev.teams.length > 0 && (
                    <div className="flex gap-1 mt-1">
                      {dev.teams.map((t) => (
                        <Badge
                          key={t.id}
                          variant="outline"
                          className="text-[10px] px-1.5 py-0"
                        >
                          {t.name}
                        </Badge>
                      ))}
                    </div>
                  )}
                </div>
              </div>
              <div className="flex items-center gap-2">
                <Label
                  htmlFor={`vis-${dev.id}`}
                  className="text-sm text-muted-foreground"
                >
                  {dev.visible ? "Visible" : "Hidden"}
                </Label>
                <Switch
                  id={`vis-${dev.id}`}
                  checked={dev.visible}
                  onCheckedChange={(checked) =>
                    toggleVisibility.mutate({ id: dev.id, visible: checked })
                  }
                  disabled={toggleVisibility.isPending}
                />
              </div>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}
