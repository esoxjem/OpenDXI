"use client";

import { motion } from "framer-motion";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import type { DeveloperMetrics } from "@/types/metrics";

interface DeveloperCardProps {
  developer: DeveloperMetrics;
  onClick: () => void;
  index?: number;
}

function getDxiBadgeVariant(score: number): "default" | "secondary" | "destructive" {
  if (score >= 70) return "default";
  if (score >= 50) return "secondary";
  return "destructive";
}

function getInitials(name: string): string {
  return name
    .split(/[\s-_]+/)
    .map((part) => part[0]?.toUpperCase() || "")
    .slice(0, 2)
    .join("");
}

export function DeveloperCard({ developer, onClick, index = 0 }: DeveloperCardProps) {
  const initials = getInitials(developer.developer);
  const linesChanged = developer.lines_added + developer.lines_deleted;

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4, delay: index * 0.05 }}
      whileHover={{ scale: 1.02 }}
      whileTap={{ scale: 0.98 }}
    >
      <Card
        className="cursor-pointer hover:border-primary/50 transition-colors"
        onClick={onClick}
      >
        <CardContent className="py-4">
          <div className="flex items-center gap-3 mb-3">
            <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center text-sm font-semibold text-primary">
              {initials}
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-medium truncate">{developer.developer}</p>
              <Badge variant={getDxiBadgeVariant(developer.dxi_score)} className="mt-1">
                DXI {developer.dxi_score.toFixed(0)}
              </Badge>
            </div>
          </div>
          <div className="grid grid-cols-3 gap-2 text-sm">
            <div>
              <p className="text-muted-foreground">Commits</p>
              <p className="font-medium">{developer.commits}</p>
            </div>
            <div>
              <p className="text-muted-foreground">PRs</p>
              <p className="font-medium">{developer.prs_merged}/{developer.prs_opened}</p>
            </div>
            <div>
              <p className="text-muted-foreground">Reviews</p>
              <p className="font-medium">{developer.reviews_given}</p>
            </div>
          </div>
          <div className="mt-2 pt-2 border-t text-xs text-muted-foreground">
            {linesChanged.toLocaleString()} lines changed
          </div>
        </CardContent>
      </Card>
    </motion.div>
  );
}
