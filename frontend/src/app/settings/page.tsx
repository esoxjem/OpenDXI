/**
 * Settings page for user, developer, and team management.
 *
 * Only accessible to users with owner role.
 * Sections:
 *   - Users: add/remove users, change roles
 *   - Developers: sync from GitHub, toggle visibility on dashboard
 *   - Teams: create/edit/delete teams, manage memberships
 */

"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { useAuth } from "@/hooks/useAuth";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
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
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  UserPlus,
  Trash2,
  Loader2,
  ArrowLeft,
  RefreshCw,
  Plus,
  ChevronDown,
  ChevronRight,
  Users,
  AlertTriangle,
  Check,
} from "lucide-react";

const API_BASE = process.env.NEXT_PUBLIC_API_URL || "http://localhost:3000";

interface User {
  id: number;
  github_id: number;
  login: string;
  name: string | null;
  avatar_url: string;
  role: "owner" | "developer";
  last_login_at: string | null;
  created_at: string;
}

interface UsersResponse {
  users: User[];
}

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

export default function SettingsPage() {
  const { user, isLoading: authLoading } = useAuth();
  const router = useRouter();
  const queryClient = useQueryClient();

  // State for Add User dialog
  const [addDialogOpen, setAddDialogOpen] = useState(false);
  const [newUserLogin, setNewUserLogin] = useState("");
  const [addError, setAddError] = useState<string | null>(null);

  // State for Delete confirmation
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [userToDelete, setUserToDelete] = useState<User | null>(null);

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
      if (context?.previousUsers) {
        queryClient.setQueryData(["users"], context.previousUsers);
      }
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ["users"] });
    },
  });

  // Add user mutation
  const addUser = useMutation({
    mutationFn: async (login: string) => {
      const res = await fetch(`${API_BASE}/api/users`, {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ login }),
      });
      const data = await res.json();
      if (!res.ok) {
        throw new Error(data.detail || "Failed to add user");
      }
      return data;
    },
    onSuccess: () => {
      setAddDialogOpen(false);
      setNewUserLogin("");
      setAddError(null);
      queryClient.invalidateQueries({ queryKey: ["users"] });
    },
    onError: (error: Error) => {
      setAddError(error.message);
    },
  });

  // Delete user mutation
  const deleteUser = useMutation({
    mutationFn: async (id: number) => {
      const res = await fetch(`${API_BASE}/api/users/${id}`, {
        method: "DELETE",
        credentials: "include",
      });
      const data = await res.json();
      if (!res.ok) {
        throw new Error(data.detail || "Failed to remove user");
      }
      return data;
    },
    onMutate: async (id) => {
      await queryClient.cancelQueries({ queryKey: ["users"] });
      const previousUsers = queryClient.getQueryData<UsersResponse>(["users"]);

      queryClient.setQueryData<UsersResponse>(["users"], (old) => {
        if (!old) return old;
        return {
          users: old.users.filter((u) => u.id !== id),
        };
      });

      return { previousUsers };
    },
    onError: (_err, _vars, context) => {
      if (context?.previousUsers) {
        queryClient.setQueryData(["users"], context.previousUsers);
      }
    },
    onSuccess: () => {
      setDeleteDialogOpen(false);
      setUserToDelete(null);
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ["users"] });
    },
  });

  // ─── Developer Management ────────────────────────────────────────────

  // Fetch managed developers (only when user is owner)
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
    enabled: user?.role === "owner",
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
        body: JSON.stringify({ visible }),
      });
      if (!res.ok) throw new Error("Failed to update visibility");
      return res.json();
    },
    onMutate: async ({ id, visible }) => {
      await queryClient.cancelQueries({ queryKey: ["managed-developers"] });
      const previous = queryClient.getQueryData<ManagedDevelopersResponse>(["managed-developers"]);

      queryClient.setQueryData<ManagedDevelopersResponse>(["managed-developers"], (old) => {
        if (!old) return old;
        return {
          developers: old.developers.map((d) =>
            d.id === id ? { ...d, visible } : d
          ),
        };
      });

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

  const visibleCount = devsData?.developers.filter((d) => d.visible).length ?? 0;
  const totalCount = devsData?.developers.length ?? 0;

  // ─── Team Management ───────────────────────────────────────────────

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
    enabled: user?.role === "owner",
  });

  // Create team mutation
  const createTeam = useMutation({
    mutationFn: async ({ name, developer_ids }: { name: string; developer_ids: number[] }) => {
      const res = await fetch(`${API_BASE}/api/teams`, {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, developer_ids }),
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
    mutationFn: async ({ id, developer_ids }: { id: number; developer_ids: number[] }) => {
      const res = await fetch(`${API_BASE}/api/teams/${id}`, {
        method: "PATCH",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ developer_ids }),
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

  const toggleMemberId = (devId: number, memberIds: number[], setMemberIds: (ids: number[]) => void) => {
    setMemberIds(
      memberIds.includes(devId)
        ? memberIds.filter((id) => id !== devId)
        : [...memberIds, devId]
    );
  };

  // Filter developers by search query for member picker
  const filterDevelopers = (search: string) => {
    if (!devsData?.developers) return [];
    if (!search.trim()) return devsData.developers;
    const q = search.toLowerCase();
    return devsData.developers.filter(
      (d) =>
        d.github_login.toLowerCase().includes(q) ||
        (d.name && d.name.toLowerCase().includes(q))
    );
  };

  const handleAddUser = (e: React.FormEvent) => {
    e.preventDefault();
    const login = newUserLogin.trim().replace(/^@/, "");
    if (!login) return;
    setAddError(null);
    addUser.mutate(login);
  };

  const handleDeleteClick = (userToRemove: User) => {
    setUserToDelete(userToRemove);
    setDeleteDialogOpen(true);
  };

  const confirmDelete = () => {
    if (userToDelete) {
      deleteUser.mutate(userToDelete.id);
    }
  };

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
      <div className="flex items-center gap-3 mb-6">
        <Link href="/">
          <Button variant="ghost" size="icon" title="Back to dashboard">
            <ArrowLeft className="h-5 w-5" />
          </Button>
        </Link>
        <h1 className="text-2xl font-bold">Settings</h1>
      </div>

      <section>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold">Users</h2>

          {/* Add User Dialog */}
          <Dialog open={addDialogOpen} onOpenChange={setAddDialogOpen}>
            <DialogTrigger asChild>
              <Button size="sm">
                <UserPlus className="h-4 w-4 mr-2" />
                Add User
              </Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Add User</DialogTitle>
                <DialogDescription>
                  Enter a GitHub username to add them to this application.
                </DialogDescription>
              </DialogHeader>
              <form onSubmit={handleAddUser}>
                <div className="grid gap-4 py-4">
                  <div className="grid gap-2">
                    <Label htmlFor="github-handle">GitHub Username</Label>
                    <Input
                      id="github-handle"
                      placeholder="username"
                      value={newUserLogin}
                      onChange={(e) => setNewUserLogin(e.target.value)}
                      disabled={addUser.isPending}
                    />
                    {addError && (
                      <p className="text-sm text-destructive">{addError}</p>
                    )}
                  </div>
                </div>
                <DialogFooter>
                  <Button
                    type="button"
                    variant="outline"
                    onClick={() => setAddDialogOpen(false)}
                    disabled={addUser.isPending}
                  >
                    Cancel
                  </Button>
                  <Button type="submit" disabled={addUser.isPending || !newUserLogin.trim()}>
                    {addUser.isPending && (
                      <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                    )}
                    Add User
                  </Button>
                </DialogFooter>
              </form>
            </DialogContent>
          </Dialog>
        </div>

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
                    <div className="flex items-center gap-2">
                      <p className="font-medium">{u.login}</p>
                      {u.id === user?.id && (
                        <span className="text-xs text-muted-foreground">(you)</span>
                      )}
                    </div>
                    {u.name && (
                      <p className="text-sm text-muted-foreground">{u.name}</p>
                    )}
                    {!u.last_login_at && (
                      <p className="text-xs text-muted-foreground italic">Never logged in</p>
                    )}
                  </div>
                </div>
                <div className="flex items-center gap-2">
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
                  <Button
                    variant="ghost"
                    size="icon"
                    onClick={() => handleDeleteClick(u)}
                    disabled={deleteUser.isPending || u.id === user?.id}
                    title={u.id === user?.id ? "You cannot remove yourself" : "Remove user"}
                  >
                    <Trash2 className="h-4 w-4 text-muted-foreground hover:text-destructive" />
                  </Button>
                </div>
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

      {/* ─── Developers Section ─────────────────────────────────────────── */}
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
              <>, detected {syncDevelopers.data.external_detected} external contributors</>
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
              Click &ldquo;Sync from GitHub&rdquo; to import your organization&apos;s members.
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
                    <AvatarImage src={dev.avatar_url} alt={dev.github_login} />
                    <AvatarFallback>
                      {dev.github_login[0]?.toUpperCase() || "?"}
                    </AvatarFallback>
                  </Avatar>
                  <div>
                    <div className="flex items-center gap-2">
                      <p className="font-medium">{dev.github_login}</p>
                      <Badge
                        variant={dev.source === "org_member" ? "secondary" : "outline"}
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
                          <Badge key={t.id} variant="outline" className="text-[10px] px-1.5 py-0">
                            {t.name}
                          </Badge>
                        ))}
                      </div>
                    )}
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <Label htmlFor={`vis-${dev.id}`} className="text-sm text-muted-foreground">
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

      {/* ─── Teams Section ──────────────────────────────────────────────── */}
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
                        Slug: {newTeamName.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")}
                      </p>
                    )}
                    {createTeamError && (
                      <p className="text-sm text-destructive">{createTeamError}</p>
                    )}
                  </div>

                  {/* Member Picker */}
                  <div className="grid gap-2">
                    <Label>Members ({selectedMemberIds.length} selected)</Label>
                    <Input
                      placeholder="Search developers..."
                      value={memberSearch}
                      onChange={(e) => setMemberSearch(e.target.value)}
                    />
                    <div className="border rounded-lg max-h-48 overflow-y-auto">
                      {filterDevelopers(memberSearch).map((dev) => {
                        const isSelected = selectedMemberIds.includes(dev.id);
                        return (
                          <button
                            key={dev.id}
                            type="button"
                            className={`flex items-center gap-2 w-full p-2 text-left text-sm hover:bg-muted/50 ${
                              isSelected ? "bg-muted" : ""
                            }`}
                            onClick={() => toggleMemberId(dev.id, selectedMemberIds, setSelectedMemberIds)}
                          >
                            <div className={`flex-shrink-0 h-4 w-4 rounded border flex items-center justify-center ${
                              isSelected ? "bg-primary border-primary" : "border-muted-foreground/30"
                            }`}>
                              {isSelected && <Check className="h-3 w-3 text-primary-foreground" />}
                            </div>
                            <Avatar className="h-5 w-5">
                              <AvatarImage src={dev.avatar_url} alt={dev.github_login} />
                              <AvatarFallback className="text-[8px]">
                                {dev.github_login[0]?.toUpperCase()}
                              </AvatarFallback>
                            </Avatar>
                            <span>{dev.github_login}</span>
                            {dev.name && (
                              <span className="text-muted-foreground">({dev.name})</span>
                            )}
                          </button>
                        );
                      })}
                      {filterDevelopers(memberSearch).length === 0 && (
                        <p className="p-3 text-sm text-muted-foreground text-center">
                          {devsData?.developers.length === 0
                            ? "Sync developers first"
                            : "No developers match"}
                        </p>
                      )}
                    </div>
                  </div>
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
                  <Button type="submit" disabled={createTeam.isPending || !newTeamName.trim()}>
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
              Create a custom team or sync from GitHub to import your organization&apos;s teams.
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
                      onClick={() => setExpandedTeamId(isExpanded ? null : team.id)}
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
                            variant={team.source === "github" ? "secondary" : "outline"}
                            className="text-[10px] px-1.5 py-0 flex-shrink-0"
                          >
                            {team.source === "github" ? "GitHub" : "Custom"}
                          </Badge>
                          {team.source === "github" && !team.synced && (
                            <Badge variant="outline" className="text-[10px] px-1.5 py-0 text-amber-600 border-amber-300 flex-shrink-0">
                              Diverged
                            </Badge>
                          )}
                        </div>
                        <p className="text-sm text-muted-foreground">
                          {team.developer_count} member{team.developer_count !== 1 ? "s" : ""}
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
                      {team.source === "github" && team.synced && isEditing && (
                        <div className="flex items-start gap-2 mt-3 mb-3 p-3 bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-800 rounded-lg text-sm">
                          <AlertTriangle className="h-4 w-4 text-amber-600 flex-shrink-0 mt-0.5" />
                          <p className="text-amber-800 dark:text-amber-200">
                            Editing members will mark this team as locally edited and prevent GitHub sync from updating its membership.
                          </p>
                        </div>
                      )}

                      {/* Member list */}
                      {!isEditing ? (
                        <>
                          <div className="mt-3 space-y-2">
                            {team.developers.length === 0 ? (
                              <p className="text-sm text-muted-foreground py-2">No members</p>
                            ) : (
                              team.developers.map((dev) => (
                                <div key={dev.id} className="flex items-center gap-2">
                                  <Avatar className="h-6 w-6">
                                    <AvatarImage src={dev.avatar_url} alt={dev.github_login} />
                                    <AvatarFallback className="text-[8px]">
                                      {dev.github_login[0]?.toUpperCase()}
                                    </AvatarFallback>
                                  </Avatar>
                                  <span className="text-sm">{dev.github_login}</span>
                                  {dev.name && (
                                    <span className="text-sm text-muted-foreground">({dev.name})</span>
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
                          {/* Editing mode — member picker */}
                          <div className="mt-3">
                            <Input
                              placeholder="Search developers..."
                              value={editMemberSearch}
                              onChange={(e) => setEditMemberSearch(e.target.value)}
                              className="mb-2"
                            />
                            <div className="border rounded-lg max-h-48 overflow-y-auto bg-background">
                              {filterDevelopers(editMemberSearch).map((dev) => {
                                const isSelected = editMemberIds.includes(dev.id);
                                return (
                                  <button
                                    key={dev.id}
                                    type="button"
                                    className={`flex items-center gap-2 w-full p-2 text-left text-sm hover:bg-muted/50 ${
                                      isSelected ? "bg-muted" : ""
                                    }`}
                                    onClick={() => toggleMemberId(dev.id, editMemberIds, setEditMemberIds)}
                                  >
                                    <div className={`flex-shrink-0 h-4 w-4 rounded border flex items-center justify-center ${
                                      isSelected ? "bg-primary border-primary" : "border-muted-foreground/30"
                                    }`}>
                                      {isSelected && <Check className="h-3 w-3 text-primary-foreground" />}
                                    </div>
                                    <Avatar className="h-5 w-5">
                                      <AvatarImage src={dev.avatar_url} alt={dev.github_login} />
                                      <AvatarFallback className="text-[8px]">
                                        {dev.github_login[0]?.toUpperCase()}
                                      </AvatarFallback>
                                    </Avatar>
                                    <span>{dev.github_login}</span>
                                  </button>
                                );
                              })}
                            </div>
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

      {/* Delete User Confirmation Dialog */}
      <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Remove User</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to remove <strong>{userToDelete?.login}</strong> from
              this application? They will lose access immediately.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={deleteUser.isPending}>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={confirmDelete}
              disabled={deleteUser.isPending}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {deleteUser.isPending && (
                <Loader2 className="h-4 w-4 mr-2 animate-spin" />
              )}
              Remove
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Delete Team Confirmation Dialog */}
      <AlertDialog open={deleteTeamDialogOpen} onOpenChange={setDeleteTeamDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete Team</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to delete the team <strong>{teamToDelete?.name}</strong>?
              This will remove the team and all its member assignments. Developer records will not be affected.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={deleteTeam.isPending}>Cancel</AlertDialogCancel>
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
    </div>
  );
}
