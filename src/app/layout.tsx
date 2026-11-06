import "../features/manufactured-completion.css";
import "./globals.css";
import "../features/production-recording-v3.css";
import "../features/quality-updates.css";
import type { Metadata } from "next";
export const metadata: Metadata = {
  title: "Factory Lean",
  icons: { icon: "/favicon.svg" },
  description: "Manufacturing and Lean operations",
};
export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body>{children}</body>
    </html>
  );
}
