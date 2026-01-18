"use client";

import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { Sprint } from "@/types/metrics";

interface SprintSelectorProps {
  sprints: Sprint[];
  value: string | undefined;
  onValueChange: (value: string) => void;
}

export function SprintSelector({
  sprints,
  value,
  onValueChange,
}: SprintSelectorProps) {
  return (
    <Select value={value} onValueChange={onValueChange}>
      <SelectTrigger className="w-[280px]">
        <SelectValue placeholder="Select a sprint" />
      </SelectTrigger>
      <SelectContent>
        {sprints.map((sprint) => (
          <SelectItem key={sprint.value} value={sprint.value}>
            {sprint.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
