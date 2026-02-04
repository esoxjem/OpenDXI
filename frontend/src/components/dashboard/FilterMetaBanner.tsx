"use client";

import type { FilterMeta } from "@/types/metrics";

interface FilterMetaBannerProps {
  filterMeta?: FilterMeta;
}

export function FilterMetaBanner({ filterMeta }: FilterMetaBannerProps) {
  if (!filterMeta) return null;

  const { total_developers, showing_developers, team_name } = filterMeta;

  return (
    <div className="flex items-center gap-2 text-sm text-muted-foreground bg-muted/50 rounded-lg px-3 py-2">
      <span>
        Showing {showing_developers} of {total_developers} developers
        {team_name && <> ({team_name})</>}
      </span>
    </div>
  );
}
