"use client";

import { Loader2 } from "lucide-react";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { Sprint } from "@/types/metrics";

interface SprintSelectorProps {
  sprints?: Sprint[];
  value: string | undefined;
  onValueChange: (value: string) => void;
  isLoading?: boolean;
}

export function SprintSelector({
  sprints,
  value,
  onValueChange,
  isLoading,
}: SprintSelectorProps) {
  if (isLoading) {
    return (
      <div
        className="flex items-center gap-2 h-10 px-3 border rounded-md bg-muted/50 w-[280px]"
        data-loading-state="loading"
        data-testid="loading-sprints"
        aria-busy="true"
        role="status"
      >
        <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" aria-hidden="true" />
        <span className="text-sm text-muted-foreground">Loading sprints...</span>
      </div>
    );
  }

  return (
    <Select value={value} onValueChange={onValueChange}>
      <SelectTrigger className="w-[280px]">
        <SelectValue placeholder="Select a sprint" />
      </SelectTrigger>
      <SelectContent>
        {sprints?.map((sprint) => (
          <SelectItem key={sprint.value} value={sprint.value}>
            {sprint.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
