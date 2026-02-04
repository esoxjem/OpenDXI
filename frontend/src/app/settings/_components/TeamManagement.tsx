/**
 * Team CRUD management section for the Settings page.
 *
 * Handles:
 *   - Listing teams with expand/collapse to see members
 *   - Creating new custom teams via dialog
 *   - Editing team membership inline
 *   - Deleting teams with confirmation dialog
 *
 * Uses the shared MemberPicker component for both create and edit flows.
 * Owns its own TanStack Query state for teams and team mutations.
 */

"use client";

import { useState } from "react";
import { useQueryClient, useQuery, useMutation } from "@tanstack/react-query";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import {
  Plus,
  Trash2,
  Loader2,
  ChevronDown,
  ChevronRight,
  Users,
  AlertTriangle,
} from "lucide-react";
import { MemberPicker } from "./MemberPicker";

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

interface TeamDeveloper {
  id: number;
  github_login: string;
  name: string | null;
  avatar_url: string;
}

interface Team {
  id: number;
  name: string;
  slug: string;
  source: "github" | "custom";
  synced: boolean;
  developer_count: number;
  developers: TeamDeveloper[];
}

interface TeamsResponse {
  teams: Team[];
}

export function TeamManagement() {
  const queryClient = useQueryClient();

  // State for team UI
  const [expandedTeamId, setExpandedTeamId] = useState<number | null>(null);
  const [createTeamDialogOpen, setCreateTeamDialogOpen] = useState(false);
  const [newTeamName, setNewTeamName] = useState("");
  const [selectedMemberIds, setSelectedMemberIds] = useState<number[]>([]);
  const [memberSearch, setMemberSearch] = useState("");
  const [createTeamError, setCreateTeamError] = useState<string | null>(null);

  // State for edit team members
  const [editingTeamId, setEditingTeamId] = useState<number | null>(null);
  const [editMemberIds, setEditMemberIds] = useState<number[]>([]);
  const [editMemberSearch, setEditMemberSearch] = useState("");

  // State for delete team confirmation
  const [deleteTeamDialogOpen, setDeleteTeamDialogOpen] = useState(false);
  const [teamToDelete, setTeamToDelete] = useState<Team | null>(null);

  // Fetch developers for member picker
  const { data: devsData } = useQuery({
    queryKey: ["managed-developers"],
    queryFn: async () => {
      const res = await fetch(`${API_BASE}/api/developers/managed`, {
        credentials: "include",
      });
      if (!res.ok) throw new Error("Failed to fetch developers");
      return res.json() as Promise<ManagedDevelopersResponse>;
    },
  });

  // Fetch teams
  const {
    data: teamsData,
    isLoading: teamsLoading,
    error: teamsError,
  } = useQuery({
    queryKey: ["teams"],
    queryFn: async () => {
      const res = await fetch(`${API_BASE}/api/teams`, {
        credentials: "include",
      });
      if (!res.ok) throw new Error("Failed to fetch teams");
      const data: TeamsResponse = await res.json();
      return data.teams;
    },
  });

  // Create team mutation
  const createTeam = useMutation({
    mutationFn: async ({
      name,
      developer_ids,
    }: {
      name: string;
      developer_ids: number[];
    }) => {
      const res = await fetch(`${API_BASE}/api/teams`, {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ team: { name, developer_ids } }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.detail || "Failed to create team");
      return data;
    },
    onSuccess: () => {
      setCreateTeamDialogOpen(false);
      setNewTeamName("");
      setSelectedMemberIds([]);
      setCreateTeamError(null);
      queryClient.invalidateQueries({ queryKey: ["teams"] });
      queryClient.invalidateQueries({ queryKey: ["managed-developers"] });
    },
    onError: (error: Error) => {
      setCreateTeamError(error.message);
    },
  });

  // Update team mutation
  const updateTeam = useMutation({
    mutationFn: async ({
      id,
      developer_ids,
    }: {
      id: number;
      developer_ids: number[];
    }) => {
      const res = await fetch(`${API_BASE}/api/teams/${id}`, {
        method: "PATCH",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ team: { developer_ids } }),
      });
      if (!res.ok) throw new Error("Failed to update team");
      return res.json();
    },
    onSuccess: () => {
      setEditingTeamId(null);
      queryClient.invalidateQueries({ queryKey: ["teams"] });
      queryClient.invalidateQueries({ queryKey: ["managed-developers"] });
    },
  });

  // Delete team mutation
  const deleteTeam = useMutation({
    mutationFn: async (id: number) => {
      const res = await fetch(`${API_BASE}/api/teams/${id}`, {
        method: "DELETE",
        credentials: "include",
      });
      if (!res.ok) throw new Error("Failed to delete team");
      return res.json();
    },
    onSuccess: () => {
      setDeleteTeamDialogOpen(false);
      setTeamToDelete(null);
      queryClient.invalidateQueries({ queryKey: ["teams"] });
      queryClient.invalidateQueries({ queryKey: ["managed-developers"] });
    },
  });

  const handleCreateTeam = (e: React.FormEvent) => {
    e.preventDefault();
    const name = newTeamName.trim();
    if (!name) return;
    setCreateTeamError(null);
    createTeam.mutate({ name, developer_ids: selectedMemberIds });
  };

  const handleDeleteTeamClick = (team: Team) => {
    setTeamToDelete(team);
    setDeleteTeamDialogOpen(true);
  };

  const confirmDeleteTeam = () => {
    if (teamToDelete) {
      deleteTeam.mutate(teamToDelete.id);
    }
  };

  const startEditingMembers = (team: Team) => {
    setEditingTeamId(team.id);
    setEditMemberIds(team.developers.map((d) => d.id));
    setEditMemberSearch("");
  };

  const saveEditingMembers = (teamId: number) => {
    updateTeam.mutate({ id: teamId, developer_ids: editMemberIds });
  };

  const allDevelopers = devsData?.developers ?? [];

  return (
    <>
      <section className="mt-8">
        <div className="flex items-center justify-between mb-4">
          <div>
            <h2 className="text-lg font-semibold">Teams</h2>
            {(teamsData?.length ?? 0) > 0 && (
              <p className="text-sm text-muted-foreground">
                {teamsData?.length} team{teamsData?.length !== 1 ? "s" : ""}
              </p>
            )}
          </div>

          {/* Create Team Dialog */}
          <Dialog
            open={createTeamDialogOpen}
            onOpenChange={(open) => {
              setCreateTeamDialogOpen(open);
              if (!open) {
                setNewTeamName("");
                setSelectedMemberIds([]);
                setMemberSearch("");
                setCreateTeamError(null);
              }
            }}
          >
            <DialogTrigger asChild>
              <Button size="sm">
                <Plus className="h-4 w-4 mr-2" />
                Create Team
              </Button>
            </DialogTrigger>
            <DialogContent className="max-w-md">
              <DialogHeader>
                <DialogTitle>Create Team</DialogTitle>
                <DialogDescription>
                  Create a custom team and assign developers.
                </DialogDescription>
              </DialogHeader>
              <form onSubmit={handleCreateTeam}>
                <div className="grid gap-4 py-4">
                  <div className="grid gap-2">
                    <Label htmlFor="team-name">Team Name</Label>
                    <Input
                      id="team-name"
                      placeholder="e.g. Backend, Platform"
                      value={newTeamName}
                      onChange={(e) => setNewTeamName(e.target.value)}
                      disabled={createTeam.isPending}
                    />
                    {newTeamName.trim() && (
                      <p className="text-xs text-muted-foreground">
                        Slug:{" "}
                        {newTeamName
                          .trim()
                          .toLowerCase()
                          .replace(/[^a-z0-9]+/g, "-")
                          .replace(/^-|-$/g, "")}
                      </p>
                    )}
                    {createTeamError && (
                      <p className="text-sm text-destructive">
                        {createTeamError}
                      </p>
                    )}
                  </div>

                  {/* Member Picker */}
                  <MemberPicker
                    developers={allDevelopers}
                    selectedIds={selectedMemberIds}
                    onSelectionChange={setSelectedMemberIds}
                    searchQuery={memberSearch}
                    onSearchChange={setMemberSearch}
                  />
                </div>
                <DialogFooter>
                  <Button
                    type="button"
                    variant="outline"
                    onClick={() => setCreateTeamDialogOpen(false)}
                    disabled={createTeam.isPending}
                  >
                    Cancel
                  </Button>
                  <Button
                    type="submit"
                    disabled={createTeam.isPending || !newTeamName.trim()}
                  >
                    {createTeam.isPending && (
                      <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                    )}
                    Create Team
                  </Button>
                </DialogFooter>
              </form>
            </DialogContent>
          </Dialog>
        </div>

        {teamsLoading ? (
          <p className="text-muted-foreground">Loading teams...</p>
        ) : teamsError ? (
          <p className="text-destructive">
            Failed to load teams. Please try again.
          </p>
        ) : (teamsData?.length ?? 0) === 0 ? (
          <div className="border rounded-lg p-8 text-center text-muted-foreground">
            <Users className="h-8 w-8 mx-auto mb-2 opacity-50" />
            <p className="mb-2">No teams yet.</p>
            <p className="text-sm">
              Create a custom team or sync from GitHub to import your
              organization&apos;s teams.
            </p>
          </div>
        ) : (
          <div className="border rounded-lg divide-y">
            {teamsData?.map((team) => {
              const isExpanded = expandedTeamId === team.id;
              const isEditing = editingTeamId === team.id;

              return (
                <div key={team.id}>
                  {/* Team header row */}
                  <div className="flex items-center justify-between p-4">
                    <button
                      className="flex items-center gap-3 text-left flex-1 min-w-0"
                      onClick={() =>
                        setExpandedTeamId(isExpanded ? null : team.id)
                      }
                    >
                      {isExpanded ? (
                        <ChevronDown className="h-4 w-4 flex-shrink-0 text-muted-foreground" />
                      ) : (
                        <ChevronRight className="h-4 w-4 flex-shrink-0 text-muted-foreground" />
                      )}
                      <div className="min-w-0">
                        <div className="flex items-center gap-2">
                          <p className="font-medium truncate">{team.name}</p>
                          <Badge
                            variant={
                              team.source === "github" ? "secondary" : "outline"
                            }
                            className="text-[10px] px-1.5 py-0 flex-shrink-0"
                          >
                            {team.source === "github" ? "GitHub" : "Custom"}
                          </Badge>
                          {team.source === "github" && !team.synced && (
                            <Badge
                              variant="outline"
                              className="text-[10px] px-1.5 py-0 text-amber-600 border-amber-300 flex-shrink-0"
                            >
                              Diverged
                            </Badge>
                          )}
                        </div>
                        <p className="text-sm text-muted-foreground">
                          {team.developer_count} member
                          {team.developer_count !== 1 ? "s" : ""}
                        </p>
                      </div>
                    </button>
                    <div className="flex items-center gap-1 flex-shrink-0">
                      <Button
                        variant="ghost"
                        size="icon"
                        onClick={() => handleDeleteTeamClick(team)}
                        disabled={deleteTeam.isPending}
                        title="Delete team"
                      >
                        <Trash2 className="h-4 w-4 text-muted-foreground hover:text-destructive" />
                      </Button>
                    </div>
                  </div>

                  {/* Expanded team details */}
                  {isExpanded && (
                    <div className="px-4 pb-4 border-t bg-muted/30">
                      {/* Divergence warning for GitHub teams */}
                      {team.source === "github" &&
                        team.synced &&
                        isEditing && (
                          <div className="flex items-start gap-2 mt-3 mb-3 p-3 bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-800 rounded-lg text-sm">
                            <AlertTriangle className="h-4 w-4 text-amber-600 flex-shrink-0 mt-0.5" />
                            <p className="text-amber-800 dark:text-amber-200">
                              Editing members will mark this team as locally
                              edited and prevent GitHub sync from updating its
                              membership.
                            </p>
                          </div>
                        )}

                      {/* Member list */}
                      {!isEditing ? (
                        <>
                          <div className="mt-3 space-y-2">
                            {team.developers.length === 0 ? (
                              <p className="text-sm text-muted-foreground py-2">
                                No members
                              </p>
                            ) : (
                              team.developers.map((dev) => (
                                <div
                                  key={dev.id}
                                  className="flex items-center gap-2"
                                >
                                  <Avatar className="h-6 w-6">
                                    <AvatarImage
                                      src={dev.avatar_url}
                                      alt={dev.github_login}
                                    />
                                    <AvatarFallback className="text-[8px]">
                                      {dev.github_login[0]?.toUpperCase()}
                                    </AvatarFallback>
                                  </Avatar>
                                  <span className="text-sm">
                                    {dev.github_login}
                                  </span>
                                  {dev.name && (
                                    <span className="text-sm text-muted-foreground">
                                      ({dev.name})
                                    </span>
                                  )}
                                </div>
                              ))
                            )}
                          </div>
                          <Button
                            variant="outline"
                            size="sm"
                            className="mt-3"
                            onClick={() => startEditingMembers(team)}
                          >
                            Edit Members
                          </Button>
                        </>
                      ) : (
                        <>
                          {/* Editing mode -- member picker */}
                          <div className="mt-3">
                            <MemberPicker
                              developers={allDevelopers}
                              selectedIds={editMemberIds}
                              onSelectionChange={setEditMemberIds}
                              searchQuery={editMemberSearch}
                              onSearchChange={setEditMemberSearch}
                            />
                            <div className="flex items-center gap-2 mt-3">
                              <Button
                                size="sm"
                                onClick={() => saveEditingMembers(team.id)}
                                disabled={updateTeam.isPending}
                              >
                                {updateTeam.isPending && (
                                  <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                                )}
                                Save ({editMemberIds.length} members)
                              </Button>
                              <Button
                                variant="outline"
                                size="sm"
                                onClick={() => setEditingTeamId(null)}
                                disabled={updateTeam.isPending}
                              >
                                Cancel
                              </Button>
                            </div>
                          </div>
                        </>
                      )}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </section>

      {/* Delete Team Confirmation Dialog */}
      <AlertDialog
        open={deleteTeamDialogOpen}
        onOpenChange={setDeleteTeamDialogOpen}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete Team</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to delete the team{" "}
              <strong>{teamToDelete?.name}</strong>? This will remove the team
              and all its member assignments. Developer records will not be
              affected.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={deleteTeam.isPending}>
              Cancel
            </AlertDialogCancel>
            <AlertDialogAction
              onClick={confirmDeleteTeam}
              disabled={deleteTeam.isPending}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {deleteTeam.isPending && (
                <Loader2 className="h-4 w-4 mr-2 animate-spin" />
              )}
              Delete Team
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
