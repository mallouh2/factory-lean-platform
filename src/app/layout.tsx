import "./globals.css";
import type { Metadata } from "next";
export const metadata: Metadata = {
  title: "Factory Lean",
  description: "Manufacturing and Lean operations",
};
export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body>{children}</body>
    </html>
  );
}
