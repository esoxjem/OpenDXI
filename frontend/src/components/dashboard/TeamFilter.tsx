"use client";

import { Users } from "lucide-react";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

interface TeamOption {
  id: number;
  name: string;
  slug: string;
  developer_count: number;
}

interface TeamFilterProps {
  teams?: TeamOption[];
  value: string | null;
  onValueChange: (slug: string | null) => void;
  isLoading?: boolean;
}

const ALL_DEVELOPERS_VALUE = "__all__";

export function TeamFilter({
  teams,
  value,
  onValueChange,
  isLoading,
}: TeamFilterProps) {
  if (isLoading || !teams || teams.length === 0) {
    return null;
  }

  return (
    <Select
      value={value ?? ALL_DEVELOPERS_VALUE}
      onValueChange={(v) => onValueChange(v === ALL_DEVELOPERS_VALUE ? null : v)}
    >
      <SelectTrigger className="w-[200px]">
        <div className="flex items-center gap-2">
          <Users className="h-4 w-4" />
          <SelectValue placeholder="All Developers" />
        </div>
      </SelectTrigger>
      <SelectContent>
        <SelectItem value={ALL_DEVELOPERS_VALUE}>All Developers</SelectItem>
        {teams.map((team) => (
          <SelectItem key={team.slug} value={team.slug}>
            {team.name} ({team.developer_count})
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
