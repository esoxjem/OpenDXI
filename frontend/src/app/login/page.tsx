/**
 * Login page for GitHub OAuth authentication.
 *
 * Displays a "Sign in with GitHub" button and handles OAuth errors.
 * Redirects to dashboard if already authenticated.
 */

"use client";

import { Suspense, useEffect } from "react";
import { useSearchParams } from "next/navigation";
import { useAuth } from "@/hooks/useAuth";
import { getLoginUrl } from "@/lib/api";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Github, AlertCircle } from "lucide-react";

const ERROR_MESSAGES: Record<string, string> = {
  not_authorized: "Access denied. Please contact an administrator to be added to this application.",
  access_denied: "You denied access to the application.",
  unknown_error: "An error occurred during authentication. Please try again.",
};

function LoginContent() {
  const { isAuthenticated, isLoading } = useAuth();
  const searchParams = useSearchParams();
  const error = searchParams.get("error");

  // Redirect to dashboard if already authenticated
  useEffect(() => {
    if (!isLoading && isAuthenticated) {
      window.location.href = "/";
    }
  }, [isAuthenticated, isLoading]);

  const handleLogin = () => {
    // Navigate to OAuth endpoint (OmniAuth configured to accept GET)
    window.location.href = getLoginUrl();
  };

  const errorMessage = error ? ERROR_MESSAGES[error] || ERROR_MESSAGES.unknown_error : null;

  if (isLoading) {
    return <LoginSkeleton />;
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl">OpenDXI Dashboard</CardTitle>
          <CardDescription>
            Sign in with GitHub to access developer experience metrics
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {errorMessage && (
            <Alert variant="destructive">
              <AlertCircle className="h-4 w-4" />
              <AlertDescription>{errorMessage}</AlertDescription>
            </Alert>
          )}

          <Button onClick={handleLogin} className="w-full" size="lg">
            <Github className="mr-2 h-5 w-5" />
            Sign in with GitHub
          </Button>

          <p className="text-xs text-muted-foreground text-center">
            You must be added by an administrator to access this application.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}

function LoginSkeleton() {
  return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary" />
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense fallback={<LoginSkeleton />}>
      <LoginContent />
    </Suspense>
  );
}
