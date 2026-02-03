/**
 * Settings page for user management.
 *
 * Only accessible to users with owner role.
 * Allows adding users by GitHub handle, removing users, and changing roles.
 */

"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/hooks/useAuth";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
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
import { UserPlus, Trash2, Loader2 } from "lucide-react";

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
      <h1 className="text-2xl font-bold mb-6">Settings</h1>

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
                  {/* Don't show delete for current user */}
                  {u.id !== user?.id && (
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => handleDeleteClick(u)}
                      disabled={deleteUser.isPending}
                      title="Remove user"
                    >
                      <Trash2 className="h-4 w-4 text-muted-foreground hover:text-destructive" />
                    </Button>
                  )}
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

      {/* Delete Confirmation Dialog */}
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
    </div>
  );
}
