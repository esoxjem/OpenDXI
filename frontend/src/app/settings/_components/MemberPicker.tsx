/**
 * Shared member picker component for selecting developers.
 *
 * Used in both the "Create Team" dialog and the inline "Edit Members" mode
 * within the team management section. Renders a searchable, scrollable list
 * of developers with checkbox-style selection.
 */

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Check } from "lucide-react";

interface MemberPickerDeveloper {
  id: number;
  github_login: string;
  name: string | null;
  avatar_url: string;
}

interface MemberPickerProps {
  /** Full list of developers available for selection */
  developers: MemberPickerDeveloper[];
  /** Currently selected developer IDs */
  selectedIds: number[];
  /** Callback when selection changes */
  onSelectionChange: (ids: number[]) => void;
  /** Current search query */
  searchQuery: string;
  /** Callback when search query changes */
  onSearchChange: (query: string) => void;
  /** Optional label override (defaults to "Members (N selected)") */
  label?: string;
  /** Message to show when no developers exist at all */
  emptyMessage?: string;
  /** Message to show when search yields no results */
  noMatchMessage?: string;
}

export function MemberPicker({
  developers,
  selectedIds,
  onSelectionChange,
  searchQuery,
  onSearchChange,
  label,
  emptyMessage = "Sync developers first",
  noMatchMessage = "No developers match",
}: MemberPickerProps) {
  const filteredDevelopers = filterBySearch(developers, searchQuery);

  const toggleMember = (devId: number) => {
    if (selectedIds.includes(devId)) {
      onSelectionChange(selectedIds.filter((id) => id !== devId));
    } else {
      onSelectionChange([...selectedIds, devId]);
    }
  };

  return (
    <div className="grid gap-2">
      <Label>{label ?? `Members (${selectedIds.length} selected)`}</Label>
      <Input
        placeholder="Search developers..."
        value={searchQuery}
        onChange={(e) => onSearchChange(e.target.value)}
      />
      <div className="border rounded-lg max-h-48 overflow-y-auto bg-background">
        {filteredDevelopers.map((dev) => {
          const isSelected = selectedIds.includes(dev.id);
          return (
            <button
              key={dev.id}
              type="button"
              className={`flex items-center gap-2 w-full p-2 text-left text-sm hover:bg-muted/50 ${
                isSelected ? "bg-muted" : ""
              }`}
              onClick={() => toggleMember(dev.id)}
            >
              <div
                className={`flex-shrink-0 h-4 w-4 rounded border flex items-center justify-center ${
                  isSelected
                    ? "bg-primary border-primary"
                    : "border-muted-foreground/30"
                }`}
              >
                {isSelected && (
                  <Check className="h-3 w-3 text-primary-foreground" />
                )}
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
        {filteredDevelopers.length === 0 && (
          <p className="p-3 text-sm text-muted-foreground text-center">
            {developers.length === 0 ? emptyMessage : noMatchMessage}
          </p>
        )}
      </div>
    </div>
  );
}

/** Filter developers by search query matching login or name */
function filterBySearch(
  developers: MemberPickerDeveloper[],
  search: string
): MemberPickerDeveloper[] {
  if (!search.trim()) return developers;
  const q = search.toLowerCase();
  return developers.filter(
    (d) =>
      d.github_login.toLowerCase().includes(q) ||
      (d.name && d.name.toLowerCase().includes(q))
  );
}
