"use client";

import * as React from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible";
import { ChevronRight, Lightbulb, Calculator } from "lucide-react";
import { cn } from "@/lib/utils";
import type { DimensionConfig } from "./dimension-config";

interface LearnMoreExpandProps {
  /** Dimension configuration with explanations and tips */
  config: DimensionConfig;
  /** The actual raw value for this dimension */
  rawValue: number | null;
  /** The score for this dimension (0-100) */
  score: number;
  /** Optional class name */
  className?: string;
}

/**
 * LearnMoreExpand - Collapsible explanation section
 *
 * Shows:
 * - How the score was calculated with the actual raw value
 * - Threshold breakdown explaining the scoring scale
 * - Improvement tips (only when score < 70)
 */
export function LearnMoreExpand({
  config,
  rawValue,
  score,
  className,
}: LearnMoreExpandProps) {
  const [isOpen, setIsOpen] = React.useState(false);
  const showTips = score < 70;

  // Format the raw value for display in explanation
  const formattedValue =
    rawValue !== null ? rawValue.toFixed(1) : "N/A";

  // Replace {value} placeholder in calculation template
  const calculationText = config.calculationTemplate.replace(
    "{value}",
    formattedValue
  );

  return (
    <Collapsible
      open={isOpen}
      onOpenChange={setIsOpen}
      className={cn("group", className)}
    >
      <CollapsibleTrigger
        className={cn(
          "flex items-center gap-1.5 text-xs font-medium transition-colors",
          "text-muted-foreground hover:text-foreground",
          "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
          "rounded-sm py-0.5 -ml-0.5 pl-0.5 pr-2"
        )}
        aria-expanded={isOpen}
      >
        <motion.span
          animate={{ rotate: isOpen ? 90 : 0 }}
          transition={{ duration: 0.15, ease: "easeOut" }}
          className="flex items-center justify-center"
        >
          <ChevronRight className="h-3.5 w-3.5" />
        </motion.span>
        <span>Learn more</span>
      </CollapsibleTrigger>

      <AnimatePresence initial={false}>
        {isOpen && (
          <CollapsibleContent forceMount asChild>
            <motion.div
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: "auto", opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
              transition={{ duration: 0.2, ease: [0.32, 0.72, 0, 1] }}
              className="overflow-hidden"
            >
              <div className="pt-3 pb-1 space-y-4">
                {/* Calculation explanation */}
                <div className="relative pl-6">
                  <Calculator className="absolute left-0 top-0.5 h-4 w-4 text-muted-foreground/70" />
                  <div className="space-y-2">
                    <h4 className="text-xs font-semibold text-foreground/90 tracking-wide uppercase">
                      How it&apos;s calculated
                    </h4>
                    <p
                      className="text-sm text-muted-foreground leading-relaxed"
                      dangerouslySetInnerHTML={{
                        __html: calculationText.replace(
                          /\*\*(.*?)\*\*/g,
                          '<strong class="text-foreground font-semibold">$1</strong>'
                        ),
                      }}
                    />
                    <ul className="space-y-1 mt-2">
                      {config.thresholdExplanation.map((line, i) => (
                        <li
                          key={i}
                          className="text-xs text-muted-foreground/80 flex items-start gap-2"
                        >
                          <span className="text-muted-foreground/40 select-none">
                            •
                          </span>
                          <span className="font-mono">{line}</span>
                        </li>
                      ))}
                    </ul>
                  </div>
                </div>

                {/* Improvement tips - only shown when score < 70 */}
                {showTips && (
                  <motion.div
                    initial={{ opacity: 0, y: -8 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: 0.1 }}
                    className="relative pl-6 pt-3 border-t border-dashed border-muted-foreground/20"
                  >
                    <Lightbulb className="absolute left-0 top-3.5 h-4 w-4 text-amber-500/70" />
                    <div className="space-y-2">
                      <h4 className="text-xs font-semibold text-amber-600 dark:text-amber-400 tracking-wide uppercase">
                        Tips to improve
                      </h4>
                      <ul className="space-y-1.5">
                        {config.improvementTips.map((tip, i) => (
                          <li
                            key={i}
                            className="text-xs text-muted-foreground leading-relaxed flex items-start gap-2"
                          >
                            <span className="text-amber-500/60 select-none mt-px">
                              →
                            </span>
                            <span>{tip}</span>
                          </li>
                        ))}
                      </ul>
                    </div>
                  </motion.div>
                )}

                {/* Perfect score celebration */}
                {score === 100 && (
                  <motion.div
                    initial={{ opacity: 0, scale: 0.95 }}
                    animate={{ opacity: 1, scale: 1 }}
                    className="flex items-center gap-2 px-3 py-2 rounded-md bg-emerald-500/10 dark:bg-emerald-500/20 border border-emerald-500/20"
                  >
                    <span className="text-lg">🎯</span>
                    <span className="text-xs font-medium text-emerald-600 dark:text-emerald-400">
                      Perfect score! Keep up the excellent work.
                    </span>
                  </motion.div>
                )}
              </div>
            </motion.div>
          </CollapsibleContent>
        )}
      </AnimatePresence>
    </Collapsible>
  );
}
