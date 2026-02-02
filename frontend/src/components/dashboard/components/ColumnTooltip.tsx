"use client";

import * as React from "react";
import { Info } from "lucide-react";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";

interface ColumnTooltipProps {
  /** The column header text */
  label: string;
  /** Tooltip content explaining the column */
  tooltip: string;
  /** Optional class name for the container */
  className?: string;
  /** Whether to show the info icon (for mobile touch affordance) */
  showIcon?: boolean;
}

/**
 * ColumnTooltip - Header cell with tooltip for leaderboard columns
 *
 * Features:
 * - Hover tooltip on desktop
 * - Info icon for mobile/touch affordance
 * - Accessible keyboard navigation
 */
export function ColumnTooltip({
  label,
  tooltip,
  className,
  showIcon = true,
}: ColumnTooltipProps) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <span
          className={cn(
            "inline-flex items-center gap-1 cursor-help",
            "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-1 rounded-sm",
            className
          )}
          tabIndex={0}
        >
          {label}
          {showIcon && (
            <Info className="h-3 w-3 text-muted-foreground/50 hover:text-muted-foreground transition-colors" />
          )}
        </span>
      </TooltipTrigger>
      <TooltipContent
        side="bottom"
        className="max-w-[280px] text-xs leading-relaxed"
        sideOffset={8}
      >
        {tooltip}
      </TooltipContent>
    </Tooltip>
  );
}
