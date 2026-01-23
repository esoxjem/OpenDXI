import { Loader2 } from "lucide-react";

interface LoadingMessageProps {
  message: string;
  className?: string;
}

export function LoadingMessage({ message, className }: LoadingMessageProps) {
  return (
    <div className={`flex items-center justify-center gap-2 py-8 text-muted-foreground ${className ?? ""}`}>
      <Loader2 className="h-4 w-4 animate-spin" />
      <span>{message}</span>
    </div>
  );
}
