import { Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";

interface LoadingMessageProps {
  message: string;
  className?: string;
  testId?: string;
}

export function LoadingMessage({ message, className, testId }: LoadingMessageProps) {
  return (
    <div
      data-loading-state="loading"
      data-loading-message={message}
      data-testid={testId}
      aria-busy="true"
      aria-live="polite"
      role="status"
      className={cn(
        "flex items-center justify-center gap-2 py-8 text-muted-foreground",
        className
      )}
    >
      <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
      <span>{message}</span>
    </div>
  );
}
