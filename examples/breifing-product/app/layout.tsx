import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Confer Briefing",
  description: "Daily briefing for HN",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
